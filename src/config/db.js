'use strict';

try { require('dotenv').config({ path: require('path').join(__dirname, '../../.env') }); } catch(e) {}

const oracledb = require('oracledb');
const fs       = require('fs');
const logger   = require('./logger');

// ── Thick mode ────────────────────────────────────────────────────────
(function initThickMode() {
  let libDir = process.env.ORACLE_CLIENT_LIB;
  if (!libDir && process.platform === 'win32') {
    const cands = ['C:\\Oracle\\instantclient_23_8','C:\\Oracle\\instantclient_23_7',
      'C:\\Oracle\\instantclient_21_13','C:\\Oracle\\instantclient_21_3',
      'C:\\oracle\\instantclient_21_3','C:\\instantclient_21_3'];
    libDir = cands.find(p => { try { return fs.statSync(p).isDirectory(); } catch { return false; } });
  }
  if (!libDir && process.platform === 'linux') {
    const cands = ['/opt/oracle/instantclient_21_15','/opt/oracle/instantclient_21_3',
      '/opt/oracle/instantclient_19_24','/usr/lib/oracle/21/client64/lib'];
    libDir = cands.find(p => { try { return fs.statSync(p).isDirectory(); } catch { return false; } });
  }
  if (libDir) {
    try { oracledb.initOracleClient({ libDir }); console.log('[db] Thick mode: ' + libDir); }
    catch(err) { if (!err.message.includes('already been called')) console.warn('[db] Thick mode failed: ' + err.message.split('\n')[0]); }
  } else { console.warn('[db] Instant Client not found — thin mode'); }
})();

oracledb.outFormat     = oracledb.OUT_FORMAT_OBJECT;
oracledb.autoCommit    = false;
oracledb.fetchAsString = [oracledb.CLOB];
oracledb.fetchAsBuffer = [oracledb.BLOB];

let pool;
let poolSecondary;

// Dead connection detection
function isDeadConn(err) {
  const m = (err && err.message) ? err.message : String(err);
  return ['NJS-003','NJS-500','ORA-03113','ORA-03114','ORA-03135',
          'ORA-01012','ORA-12571','ORA-12537','ORA-12547','ORA-12170'].some(c => m.includes(c));
}

async function getFreshConn() {
  return oracledb.getConnection('crmsPool');
}

async function getFreshSecondaryConn() {
  return oracledb.getConnection('crmsPoolSecondary');
}

// ── connect ───────────────────────────────────────────────────────────
async function connect() {
  if (pool) return pool;
  const dbUser = process.env.DB_USER;
  const dbPass = process.env.DB_PASSWORD;
  const dbConn = process.env.DB_CONNECTION_STRING;
  if (!dbUser || !dbPass || !dbConn)
    throw new Error('Missing DB_USER / DB_PASSWORD / DB_CONNECTION_STRING in .env');
console.log("DB_USER =", dbUser);
console.log("DB_CONNECTION_STRING =", dbConn);
console.log("DB_PASSWORD length =", dbPass?.length);
  pool = await oracledb.createPool({
    user: dbUser, password: dbPass, connectionString: dbConn,
    poolMin:          parseInt(process.env.DB_POOL_MIN,  10) || 2,
    poolMax:          parseInt(process.env.DB_POOL_MAX,  10) || 15,
    poolIncrement:    parseInt(process.env.DB_POOL_INCREMENT, 10) || 1,
    poolTimeout:      parseInt(process.env.DB_POOL_TIMEOUT,   10) || 60,
    poolPingInterval: 10,   // ping every 10s — kills stale connections fast
    poolAlias:        'crmsPool',
    stmtCacheSize:    100,
    connectTimeout:   15,
  });

  logger.info('Oracle pool ready → ' + dbConn);

  // Attempt to create secondary (DB2) pool for multi-DB authentication
  try {
    await connectSecondary();
  } catch (err) {
    logger.warn('[db] Secondary pool not available — single-DB mode: ' + (err.message || '').split('\n')[0]);
  }

  return pool;
}

async function disconnect() {
  if (pool) {
    await pool.close(10);
    pool = null;
  }
  await disconnectSecondary();
}

// ── Request-scoped connection ─────────────────────────────────────────
const asyncLocalStorage = (() => {
  try { return new (require('node:async_hooks').AsyncLocalStorage)(); } catch(e) { return null; }
})();

async function requestConnection(req, res, next) {
  // Per-request connection disabled — each DB call gets its own connection
  // and closes it immediately. This prevents connection pool exhaustion
  // caused by conn.close() hanging in thin mode.
  next();
}

// ── executeOne: run sql on conn, retry with fresh conn if dead ────────
async function executeOne(conn, sql, binds, opts) {
  try {
    return await conn.execute(sql, binds, opts);
  } catch(err) {
    if (!isDeadConn(err)) throw err;
    logger.warn('[db] Dead conn, retrying: ' + err.message.split('\n')[0]);
    const fresh = await getFreshConn();
    try    { return await fresh.execute(sql, binds, opts); }
    finally { try { await fresh.close(); } catch(e) {} }
  }
}

// ── execute ───────────────────────────────────────────────────────────
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


/**
 * callFunction(sql, binds)
 * ──────────────────────────────────────────────────────────────────
 * Executes a PL/SQL anonymous block that calls a stored function/procedure.
 * Used specifically for FND_WEB_SEC.VALIDATE_LOGIN which requires
 * OUT parameters — something plain query() cannot handle.
 *
 * Example usage in authController.js:
 *   const result = await db.callFunction(
 *     'BEGIN :ret := FND_WEB_SEC.VALIDATE_LOGIN(:user, :pass); END;',
 *     {
 *       ret:  { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 100 },
 *       user: { dir: oracledb.BIND_IN,  val: 'JOHN.SMITH' },
 *       pass: { dir: oracledb.BIND_IN,  val: 'mypassword' },
 *     }
 *   );
 *   // result.outBinds.ret === 'Y' means valid credentials
 */
async function callFunction(sql, binds = {}) {
  const stored = asyncLocalStorage ? asyncLocalStorage.getStore() : null;
  const conn   = stored || await getFreshConn();
  try {
    const result = await conn.execute(sql, binds, { autoCommit: false });
    return result;
  } catch(err) {
    if (!isDeadConn(err)) throw err;
    logger.warn('[db] Dead conn in callFunction, retrying: ' + err.message.split('\n')[0]);
    const fresh = await getFreshConn();
    try    { return await fresh.execute(sql, binds, { autoCommit: false }); }
    finally { try { await fresh.close(); } catch(e) {} }
  } finally {
    if (!stored) { try { await conn.close(); } catch(e) {} }
  }
}

// ═════════════════════════════════════════════════════════════════════
// SECONDARY (DB2) POOL — for multi-DB authentication
// ═════════════════════════════════════════════════════════════════════
// These methods mirror the existing helpers but use the secondary pool.
// They are used exclusively by authController for logging in users
// whose accounts live in a different Oracle DB instance.
// ═════════════════════════════════════════════════════════════════════

async function connectSecondary() {
  if (poolSecondary) return poolSecondary;
  const dbUser2 = process.env.DB2_USER;
  const dbPass2 = process.env.DB2_PASSWORD;
  const dbConn2 = process.env.DB2_CONNECTION_STRING;
  if (!dbUser2 || !dbPass2 || !dbConn2) {
    logger.warn('[db] DB2 not configured (DB2_USER/DB2_PASSWORD/DB2_CONNECTION_STRING) — skipping secondary pool');
    return null;
  }
  poolSecondary = await oracledb.createPool({
    user: dbUser2, password: dbPass2, connectionString: dbConn2,
    poolMin:          parseInt(process.env.DB_POOL_MIN,  10) || 1,
    poolMax:          parseInt(process.env.DB_POOL_MAX,  10) || 5,
    poolIncrement:    parseInt(process.env.DB_POOL_INCREMENT, 10) || 1,
    poolTimeout:      parseInt(process.env.DB_POOL_TIMEOUT,   10) || 60,
    poolPingInterval: 10,
    poolAlias:        'crmsPoolSecondary',
    stmtCacheSize:    100,
    connectTimeout:   15,
  });
  logger.info('Oracle secondary pool ready → ' + dbConn2);
  return poolSecondary;
}

async function disconnectSecondary() {
  if (!poolSecondary) return;
  await poolSecondary.close(10);
  poolSecondary = null;
}

async function executeOneSecondary(conn, sql, binds, opts) {
  try {
    return await conn.execute(sql, binds, opts);
  } catch(err) {
    if (!isDeadConn(err)) throw err;
    logger.warn('[db] Dead secondary conn, retrying: ' + err.message.split('\n')[0]);
    const fresh = await getFreshSecondaryConn();
    try    { return await fresh.execute(sql, binds, opts); }
    finally { try { await fresh.close(); } catch(e) {} }
  }
}

async function executeSecondary(sql, binds = {}, opts = {}) {
  if (!poolSecondary) throw new Error('Secondary DB pool not connected');
  const o = { outFormat: oracledb.OUT_FORMAT_OBJECT, autoCommit: false, ...opts };
  const conn = await getFreshSecondaryConn();
  try    { return await executeOneSecondary(conn, sql, binds, o); }
  finally { try { await conn.close(); } catch(e) {} }
}

async function executeWithCommitSecondary(sql, binds = {}, opts = {}) {
  if (!poolSecondary) throw new Error('Secondary DB pool not connected');
  const o = { outFormat: oracledb.OUT_FORMAT_OBJECT, autoCommit: false, ...opts };
  const conn = await getFreshSecondaryConn();
  try    { return await executeOneSecondary(conn, sql, binds, { ...o, autoCommit: true }); }
  finally { try { await conn.close(); } catch(e) {} }
}

async function querySecondary(sql, binds = {}) {
  return (await executeSecondary(sql, binds)).rows || [];
}

async function queryOneSecondary(sql, binds = {}) {
  return (await querySecondary(sql, binds))[0] || null;
}

async function callFunctionSecondary(sql, binds = {}) {
  if (!poolSecondary) throw new Error('Secondary DB pool not connected');
  const conn = await getFreshSecondaryConn();
  try {
    return await conn.execute(sql, binds, { autoCommit: false });
  } catch(err) {
    if (!isDeadConn(err)) throw err;
    logger.warn('[db] Dead secondary conn in callFunction, retrying: ' + err.message.split('\n')[0]);
    const fresh = await getFreshSecondaryConn();
    try    { return await fresh.execute(sql, binds, { autoCommit: false }); }
    finally { try { await fresh.close(); } catch(e) {} }
  } finally {
    try { await conn.close(); } catch(e) {}
  }
}

function isSecondaryReady() {
  return !!poolSecondary;
}

module.exports = {
  connect, disconnect, requestConnection,
  execute, executeWithCommit, transaction, query, queryOne,
  callFunction,
  connectSecondary, disconnectSecondary, isSecondaryReady,
  executeSecondary, executeWithCommitSecondary,
  querySecondary, queryOneSecondary,
  callFunctionSecondary,
  // Expose oracledb constants so callers can use BIND_IN/BIND_OUT/STRING etc.
  oracledb,
};
