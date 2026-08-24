'use strict';

try { require('dotenv').config(); } catch(e) {}

const oracledb = require('oracledb');
const fs       = require('fs');
const logger   = require('./logger');

// ── Thick mode ─────────────────────────────────────────────────────────
(function initThickMode() {
  let libDir = process.env.ORACLE_CLIENT_LIB;
  if (!libDir && process.platform === 'win32') {
    const cands = ['C:\\\\Oracle\\\\instantclient_23_8','C:\\\\Oracle\\\\instantclient_23_7',
      'C:\\\\Oracle\\\\instantclient_21_13','C:\\\\Oracle\\\\instantclient_21_3',
      'C:\\\\oracle\\\\instantclient_21_3','C:\\\\instantclient_21_3'];
    libDir = cands.find(p => { try { return fs.statSync(p).isDirectory(); } catch { return false; } });
  }
  if (!libDir && process.platform === 'linux') {
    const cands = ['/opt/oracle/instantclient_21_15','/opt/oracle/instantclient_21_3',
      '/opt/oracle/instantclient_19_24','/usr/lib/oracle/21/client64/lib'];
    libDir = cands.find(p => { try { return fs.statSync(p).isDirectory(); } catch { return false; } });
  }
  if (libDir) {
    try { oracledb.initOracleClient({ libDir }); console.log('[db] Thick mode: ' + libDir); }
    catch(err) { if (!err.message.includes('already been called')) console.warn('[db] Thick mode failed: ' + err.message.split('\\n')[0]); }
  } else { console.warn('[db] Instant Client not found — thin mode'); }
})();

oracledb.outFormat     = oracledb.OUT_FORMAT_OBJECT;

// Schema prefix — set DB_SCHEMA in .env if tables are owned by a different schema
// e.g. DB_SCHEMA=CRMS_OWNER means all queries use CRMS_OWNER.crms_users etc.
// If DB_SCHEMA not set, no prefix is used (tables accessed directly)
const SCHEMA_PREFIX = process.env.DB_SCHEMA ? process.env.DB_SCHEMA.toUpperCase() + '.' : '';

// tbl(name) — returns schema-prefixed table name
// Usage: db.query('SELECT * FROM ' + db.tbl('crms_users'), {})
function tbl(tableName) { return SCHEMA_PREFIX + tableName; }

oracledb.autoCommit    = false;
oracledb.fetchAsString = [oracledb.CLOB];
oracledb.fetchAsBuffer = [oracledb.BLOB];

// ── Pool references ────────────────────────────────────────────────────
let pool     = null;   // main data pool  — DB2 (all CRMS tables)
let authPool = null;   // auth-only pool  — DB1 (FND_WEB_SEC login validation)

// Dead connection detection
function isDeadConn(err) {
  const m = (err && err.message) ? err.message : String(err);
  return ['NJS-003','NJS-500','ORA-03113','ORA-03114','ORA-03135',
          'ORA-01012','ORA-12571','ORA-12537','ORA-12547','ORA-12170'].some(c => m.includes(c));
}

async function getFreshConn() {
  return oracledb.getConnection('crmsPool');
}

// ── connect ────────────────────────────────────────────────────────────
// Called by connectWithRetry in server.js — safe to call multiple times.
async function connect() {
  // ── Guard: if main pool already exists and is open, skip ─────────
  if (pool) {
    try {
      // Check pool is still alive
      const status = pool.status;
      if (status === oracledb.POOL_STATUS_OPEN) return pool;
    } catch(e) { /* pool gone — recreate below */ }
    pool = null;
  }

  const dbUser = process.env.DB_USER;
  const dbPass = process.env.DB_PASSWORD;
  const dbConn = process.env.DB_CONNECTION_STRING;
  if (!dbUser || !dbPass || !dbConn)
    throw new Error('Missing DB_USER / DB_PASSWORD / DB_CONNECTION_STRING in .env');
  // DB_SCHEMA: if CRMS tables were created under a different schema than DB_USER,
  // set DB_SCHEMA=THAT_SCHEMA in .env so queries use SCHEMA.table_name format.
  if (SCHEMA_PREFIX) logger.info('[db] Using schema prefix: ' + SCHEMA_PREFIX);

  // ── Drop stale pool alias if it exists (prevents NJS-046) ────────
  try {
    const existing = oracledb.getPool('crmsPool');
    if (existing) { await existing.close(0).catch(() => {}); }
  } catch(e) { /* pool did not exist — fine */ }

  pool = await oracledb.createPool({
    user: dbUser, password: dbPass, connectionString: dbConn,
    poolMin:          parseInt(process.env.DB_POOL_MIN,  10) || 2,
    poolMax:          parseInt(process.env.DB_POOL_MAX,  10) || 15,
    poolIncrement:    parseInt(process.env.DB_POOL_INCREMENT, 10) || 1,
    poolTimeout:      parseInt(process.env.DB_POOL_TIMEOUT,   10) || 60,
    poolPingInterval: 10,
    poolAlias:        'crmsPool',
    stmtCacheSize:    100,
    connectTimeout:   15,
  });
  logger.info('Oracle data pool ready → ' + dbConn);

  // ── Auth pool (DB1) — only if separate auth DB is configured ─────
  if (process.env.AUTH_DB_CONNECTION_STRING) {
    if (authPool) {
      try { await authPool.close(0).catch(() => {}); } catch(e) {}
      authPool = null;
    }
    try {
      // Drop stale alias
      try { const ep = oracledb.getPool('crmsAuthPool'); if(ep) await ep.close(0).catch(()=>{}); } catch(e) {}

      authPool = await oracledb.createPool({
        user:             process.env.AUTH_DB_USER     || dbUser,
        password:         process.env.AUTH_DB_PASSWORD || dbPass,
        connectionString: process.env.AUTH_DB_CONNECTION_STRING,
        poolMin:       1,
        poolMax:       5,
        poolPingInterval: 30,
        poolAlias:     'crmsAuthPool',
        connectTimeout: 15,
      });
      logger.info('Oracle auth pool ready (DB1) → ' + process.env.AUTH_DB_CONNECTION_STRING);
    } catch(authErr) {
      logger.warn('Auth pool (DB1) failed to init — login will use data pool: ' + authErr.message);
      authPool = null;
    }
  }

  return pool;
}

async function disconnect() {
  if (authPool) { try { await authPool.close(10); } catch(e) {} authPool = null; }
  if (pool)     { try { await pool.close(10);     } catch(e) {} pool = null; }
}

// ── validateLogin ──────────────────────────────────────────────────────
// Uses DB1 (authPool) if configured, falls back to data pool (DB2).
// Returns true/false — does NOT throw on invalid credentials.
// validateLogin: returns 'Y'|'N'|throws
// 'Y'    = valid credentials
// 'N'    = invalid password (FND returned N or ORA-01017)
// throws = real error (ORA-04067 unavailable, ORA-28000 locked, etc.)
async function validateLogin(username, password) {
  const targetPool = authPool || pool;
  const conn = await targetPool.getConnection();
  try {
    const result = await conn.execute(
      'BEGIN :ret := FND_WEB_SEC.VALIDATE_LOGIN(:u, :p); END;',
      {
        ret: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 10 },
        u:   { dir: oracledb.BIND_IN,  val: String(username).toUpperCase() },
        p:   { dir: oracledb.BIND_IN,  val: String(password) }
      },
      { autoCommit: false }
    );
    const ret = (result.outBinds && result.outBinds.ret) || 'N';
    return ret; // 'Y' or 'N'
  } catch(err) {
    const msg = err.message || '';
    // ORA-01017 = invalid username/password — return 'N' cleanly
    if (msg.includes('ORA-01017')) return 'N';
    // Any other error = real problem (unavailable, locked, network)
    // Re-throw so the caller can handle it correctly
    throw err;
  } finally {
    try { await conn.close(); } catch(e) {}
  }
}

// ── Request-scoped connection ──────────────────────────────────────────
const asyncLocalStorage = (() => {
  try { return new (require('node:async_hooks').AsyncLocalStorage)(); } catch(e) { return null; }
})();

async function requestConnection(req, res, next) {
  const skip = ['/auth/users','/auth/login','/auth/refresh'];
  if (skip.some(p => (req.path||'').endsWith(p))) return next();
  if (!pool || !asyncLocalStorage) return next();

  let conn, released = false;
  const release = async () => {
    if (released) return; released = true;
    if (conn) { try { await conn.close(); } catch(e) {} }
  };
  try {
    conn = await getFreshConn();
    res.on('finish', release);
    res.on('close',  release);
    asyncLocalStorage.run(conn, next);
  } catch(err) {
    logger.warn('[db] requestConnection failed — per-query mode: ' + err.message);
    next();
  }
}

async function executeOne(conn, sql, binds, opts) {
  try {
    return await conn.execute(sql, binds, opts);
  } catch(err) {
    if (!isDeadConn(err)) throw err;
    logger.warn('[db] Dead conn, retrying: ' + err.message.split('\\n')[0]);
    const fresh = await getFreshConn();
    try    { return await fresh.execute(sql, binds, opts); }
    finally { try { await fresh.close(); } catch(e) {} }
  }
}

async function execute(sql, binds = {}, opts = {}) {
  const o = { outFormat: oracledb.OUT_FORMAT_OBJECT, autoCommit: false, ...opts };
  const stored = asyncLocalStorage ? asyncLocalStorage.getStore() : null;
  if (stored) return executeOne(stored, sql, binds, o);
  const conn = await getFreshConn();
  try    { return await executeOne(conn, sql, binds, o); }
  finally { try { await conn.close(); } catch(e) {} }
}

async function executeWithCommit(sql, binds = {}, opts = {}) {
  const o = { outFormat: oracledb.OUT_FORMAT_OBJECT, autoCommit: false, ...opts };
  const stored = asyncLocalStorage ? asyncLocalStorage.getStore() : null;
  if (stored) {
    const r = await executeOne(stored, sql, binds, o);
    await stored.commit();
    return r;
  }
  const conn = await getFreshConn();
  try    { return await executeOne(conn, sql, binds, { ...o, autoCommit: true }); }
  finally { try { await conn.close(); } catch(e) {} }
}

async function transaction(fn) {
  const stored = asyncLocalStorage ? asyncLocalStorage.getStore() : null;
  const conn   = stored || await getFreshConn();
  try {
    const result = await fn(conn);
    if (!stored) await conn.commit();
    return result;
  } catch(err) {
    if (!stored) { try { await conn.rollback(); } catch(e) {} }
    throw err;
  } finally {
    if (!stored) { try { await conn.close(); } catch(e) {} }
  }
}

async function query(sql, binds = {}) {
  return (await execute(sql, binds)).rows || [];
}

async function queryOne(sql, binds = {}) {
  return (await query(sql, binds))[0] || null;
}

async function callFunction(sql, binds = {}) {
  const stored = asyncLocalStorage ? asyncLocalStorage.getStore() : null;
  const conn   = stored || await getFreshConn();
  try {
    const result = await conn.execute(sql, binds, { autoCommit: false });
    return result;
  } catch(err) {
    if (!isDeadConn(err)) throw err;
    logger.warn('[db] Dead conn in callFunction, retrying: ' + err.message.split('\\n')[0]);
    const fresh = await getFreshConn();
    try    { return await fresh.execute(sql, binds, { autoCommit: false }); }
    finally { try { await fresh.close(); } catch(e) {} }
  } finally {
    if (!stored) { try { await conn.close(); } catch(e) {} }
  }
}

module.exports = {
  connect, disconnect, requestConnection,
  execute, executeWithCommit, transaction, query, queryOne,
  callFunction,
  validateLogin,
  tbl,
  oracledb,
};
