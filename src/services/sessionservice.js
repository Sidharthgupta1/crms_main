'use strict';

const crypto = require('crypto');
const db     = require('../config/db');
const logger = require('../config/logger');

// ── Config from .env ────────────────────────────────────────────────
const SESSION_MAX_AGE_MS   = parseDurationMs(process.env.SESSION_MAX_AGE   || '8h');
const IDLE_TIMEOUT_MS      = parseDurationMs(process.env.SESSION_IDLE_TIMEOUT || '30m');
const REFRESH_COOKIE_NAME  = process.env.JWT_REFRESH_COOKIE_NAME || 'crms_refresh';
const PURGE_RETENTION_DAYS = parseInt(process.env.SESSION_PURGE_DAYS, 10) || 90;
const TOUCH_THRESHOLD_MIN  = 5; // only update last_activity if older than 5 min

function parseDurationMs(str) {
  const m = String(str).match(/^(\d+)(s|m|h|d)$/);
  if (!m) return 8 * 3600 * 1000;
  const n = parseInt(m[1], 10);
  switch (m[2]) {
    case 's': return n * 1000;
    case 'm': return n * 60 * 1000;
    case 'h': return n * 3600 * 1000;
    case 'd': return n * 86400 * 1000;
    default:  return 8 * 3600 * 1000;
  }
}

  // ── Helper: minutes between two TIMESTAMPs (Oracle interval-safe) ─
  // SYSTIMESTAMP - TIMESTAMP gives INTERVAL DAY TO SECOND which cannot
  // be multiplied by a number.  Cast to DATE first (gives NUMBER in days),
  // then multiply by 1440 for minutes.
  function minutesBetweenTimestamps(later, earlier) {
    return '(CAST(' + later + ' AS DATE) - CAST(' + earlier + ' AS DATE)) * 1440';
  }

  // ── Hash a refresh token (SHA-256) ─────────────────────────────────
  function hashRefreshToken(token) {
    if (!token) return '__pending__';
    return crypto.createHash('sha256').update(token).digest('hex');
  }

  // ── Generate a device fingerprint from request ──────────────────────
function fingerprintDevice(req) {
  const ua = req.headers['user-agent'] || '';
  const ip = req.headers['x-forwarded-for']
           || req.headers['x-real-ip']
           || (req.connection && req.connection.remoteAddress)
           || '';

  let browser = 'Unknown';
  let os      = 'Unknown';

  if (/Edg\//.test(ua))       browser = 'Edge';
  else if (/OPR\//.test(ua))  browser = 'Opera';
  else if (/Chrome/.test(ua)) browser = 'Chrome';
  else if (/Firefox/.test(ua))browser = 'Firefox';
  else if (/Safari/.test(ua)) browser = 'Safari';
  else if (/MSIE|Trident/.test(ua)) browser = 'IE';

  if (/Windows NT 10/.test(ua))       os = 'Windows 10/11';
  else if (/Windows NT 6\.3/.test(ua)) os = 'Windows 8.1';
  else if (/Windows NT 6\.1/.test(ua)) os = 'Windows 7';
  else if (/Windows/.test(ua))         os = 'Windows';
  else if (/Mac OS X/.test(ua))        os = 'macOS';
  else if (/Linux/.test(ua))           os = 'Linux';
  else if (/Android/.test(ua))         os = 'Android';
  else if (/iPhone|iPad/.test(ua))     os = 'iOS';

  const deviceName = browser + ' on ' + os;
  const deviceId = crypto
    .createHash('sha256')
    .update(browser + '|' + os + '|' + ip.split(',')[0].trim())
    .digest('hex')
    .slice(0, 64);

  return { deviceId, deviceName, browser, os, ip: ip.split(',')[0].trim(), userAgent: ua };
}

// ── Check if user_sessions table exists (cached) ───────────────────
let _tableExists = null;
async function tableExists() {
  if (_tableExists !== null) return _tableExists;
  try {
    await db.queryOne("SELECT COUNT(*) AS cnt FROM user_sessions WHERE ROWNUM=1", {});
    _tableExists = true;
  } catch(e) {
    const msg = (e.message || '').toUpperCase();
    if (msg.includes('ORA-00942') || msg.includes('TABLE OR VIEW DOES NOT EXIST')) {
      _tableExists = false;
      logger.warn('USER_SESSIONS table not found — session management disabled until migration is run');
    } else {
      _tableExists = true; // table exists but another error
    }
  }
  return _tableExists;
}

// ── Create a new session row ────────────────────────────────────────
async function createSession(userId, refreshToken, req) {
  if (!(await tableExists())) {
    return { sessionId: null, deviceId: null, expiresAt: null };
  }

  const oracledb = db.oracledb;
  const hash    = hashRefreshToken(refreshToken);
  const device  = fingerprintDevice(req);
  const now     = new Date();
  const expiresAt = new Date(now.getTime() + SESSION_MAX_AGE_MS);

  // Use db.transaction (autoCommit: false) so RETURNING INTO OUT binds work
  const result = await db.transaction(async (conn) => {
    return await conn.execute(
      `INSERT INTO user_sessions
         (user_id, refresh_token_hash, device_id, device_name, browser,
          operating_system, ip_address, user_agent, status,
          created_at, last_activity, session_expires_at)
       VALUES
         (:userId, :hash, :deviceId, :deviceName, :browser,
          :os, :ip, :userAgent, 'ACTIVE',
          SYSTIMESTAMP, SYSTIMESTAMP, :expiresAt)
       RETURNING session_id INTO :outId`,
      {
        userId,
        hash,
        deviceId:    device.deviceId,
        deviceName:  device.deviceName,
        browser:     device.browser,
        os:          device.os,
        ip:          device.ip,
        userAgent:   device.userAgent,
        expiresAt,
        outId: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER },
      },
      { outFormat: oracledb.OUT_FORMAT_OBJECT }
    );
  });

  const sessionId = result.outBinds && result.outBinds.outId
    ? result.outBinds.outId[0]
    : null;

  logger.info('Session created', { userId, sessionId, browser: device.browser, os: device.os });

  return { sessionId, deviceId: device.deviceId, expiresAt };
}

// ── Find a session by session_id (primary key) ─────────────────────
async function findSessionById(sessionId) {
  if (!(await tableExists())) return null;
  return await db.queryOne(
    `SELECT session_id, user_id, refresh_token_hash, device_id, device_name,
            browser, operating_system, ip_address, user_agent, status,
            created_at, last_activity, session_expires_at, revoked_at
       FROM user_sessions
      WHERE session_id = :sessionId`,
    { sessionId }
  );
}

// ── Validate + touch session (SELECT + conditional UPDATE) ──────────
// Returns { valid: true } if session is active, not expired, and not idle.
// Returns { valid: false, reason, code } with the specific failure reason.
// Touches last_activity ONLY if it is older than TOUCH_THRESHOLD_MIN minutes.
async function validateAndTouchSession(sessionId) {
  if (!(await tableExists()) || !sessionId) {
    return { valid: false, reason: 'NOT_FOUND', code: 'SESSION_NOT_FOUND' };
  }

  try {
    // Step 1: Validate (read-only SELECT — no lock, no write)
    const sess = await db.queryOne(
      `SELECT session_id, status, last_activity, session_expires_at
         FROM user_sessions
        WHERE session_id = :sessionId
          AND status = 'ACTIVE'
          AND session_expires_at > SYSTIMESTAMP
          AND ${minutesBetweenTimestamps('SYSTIMESTAMP', 'last_activity')} <= :idleMinutes`,
      { sessionId, idleMinutes: IDLE_TIMEOUT_MS / 60000 }
    );

    if (sess) {
      // Step 2: Valid — conditionally touch (only if last_activity > 5 min old)
      // The WHERE clause ensures no write happens when last_activity is recent.
      await db.executeWithCommit(
        `UPDATE user_sessions
            SET last_activity = SYSTIMESTAMP
          WHERE session_id = :sessionId
            AND ${minutesBetweenTimestamps('SYSTIMESTAMP', 'last_activity')} > :touchThreshold`,
        { sessionId, touchThreshold: TOUCH_THRESHOLD_MIN }
      );
      return { valid: true };
    }

    // Step 3: Invalid — determine reason with a single SELECT
    const row = await db.queryOne(
      `SELECT session_id, status, last_activity, session_expires_at
         FROM user_sessions WHERE session_id = :sessionId`,
      { sessionId }
    );

    if (!row) {
      return { valid: false, reason: 'NOT_FOUND', code: 'SESSION_NOT_FOUND' };
    }

    if (row.STATUS !== 'ACTIVE') {
      return { valid: false, reason: row.STATUS, code: 'SESSION_' + row.STATUS };
    }

    // ACTIVE but failed WHERE conditions → determine if expired or idle
    const now = new Date();
    if (new Date(row.SESSION_EXPIRES_AT) < now) {
      await expireSession(sessionId);
      return { valid: false, reason: 'EXPIRED', code: 'SESSION_EXPIRED' };
    }

    const idleMs = now.getTime() - new Date(row.LAST_ACTIVITY).getTime();
    if (idleMs > IDLE_TIMEOUT_MS) {
      await expireSession(sessionId);
      return { valid: false, reason: 'IDLE_TIMEOUT', code: 'SESSION_IDLE_TIMEOUT' };
    }

    return { valid: false, reason: 'INVALID', code: 'SESSION_INVALID' };
  } catch (e) {
    // Graceful degradation: if table doesn't exist, fall back to JWT-only
    const msg = (e.message || '').toUpperCase();
    if (msg.includes('ORA-00942') || msg.includes('TABLE OR VIEW DOES NOT EXIST')) {
      logger.warn('USER_SESSIONS table not found — falling back to JWT-only auth');
      return { valid: true };
    }
    logger.warn('validateAndTouchSession error', { error: e.message });
    return { valid: false, reason: 'INVALID', code: 'SESSION_INVALID' };
  }
}

// ── Find a session by refresh token hash ────────────────────────────
async function findSessionByTokenHash(hash) {
  if (!(await tableExists())) return null;
  return await db.queryOne(
    `SELECT session_id, user_id, refresh_token_hash, device_id, device_name,
            browser, operating_system, ip_address, user_agent, status,
            created_at, last_activity, session_expires_at, revoked_at
       FROM user_sessions
      WHERE refresh_token_hash = :hash`,
    { hash }
  );
}

// ── Rotate session: replace refresh token hash ──────────────────────
async function rotateSession(sessionId, newRefreshToken) {
  if (!(await tableExists()) || !sessionId) return null;
  const newHash = hashRefreshToken(newRefreshToken);
  await db.executeWithCommit(
    `UPDATE user_sessions
       SET refresh_token_hash = :newHash,
           last_activity      = SYSTIMESTAMP
     WHERE session_id = :sessionId`,
    { newHash, sessionId }
  );
  return newHash;
}

// ── Revoke a single session ─────────────────────────────────────────
async function revokeSession(sessionId) {
  if (!(await tableExists()) || !sessionId) {
    logger.warn('revokeSession: skipped', { sessionId, tableExists: await tableExists() });
    return 0;
  }
  const r = await db.executeWithCommit(
    `UPDATE user_sessions
       SET status = 'REVOKED', revoked_at = SYSTIMESTAMP
     WHERE session_id = :sessionId AND status = 'ACTIVE'`,
    { sessionId }
  );
  const count = r ? (r.rowsAffected || 0) : 0;
  logger.info('revokeSession: UPDATE executed', { sessionId, rowsAffected: count });
  return count;
}

// ── Expire a session (idle timeout or absolute expiry) ───────────────
async function expireSession(sessionId) {
  if (!(await tableExists()) || !sessionId) return 0;
  const r = await db.executeWithCommit(
    `UPDATE user_sessions
       SET status = 'EXPIRED', revoked_at = SYSTIMESTAMP
     WHERE session_id = :sessionId AND status = 'ACTIVE'`,
    { sessionId }
  );
  const count = r ? (r.rowsAffected || 0) : 0;
  logger.info('expireSession: UPDATE executed', { sessionId, rowsAffected: count });
  return count;
}

// ── Get all sessions for a user ─────────────────────────────────────
async function getActiveSessions(userId) {
  if (!(await tableExists())) return [];
  const rows = await db.query(
    `SELECT session_id, device_id, device_name, browser, operating_system,
            ip_address, user_agent, status, created_at, last_activity,
            session_expires_at, revoked_at
       FROM user_sessions
      WHERE user_id = :userId
      ORDER BY last_activity DESC`,
    { userId }
  );
  return rows;
}

// ── Expire stale sessions (batch: expired + idle beyond timeout) ───
async function cleanupExpiredSessions() {
  if (!(await tableExists())) return 0;
  const r = await db.executeWithCommit(
    `UPDATE user_sessions
       SET status = 'EXPIRED', revoked_at = SYSTIMESTAMP
     WHERE status = 'ACTIVE'
       AND (session_expires_at < SYSTIMESTAMP
             OR ${minutesBetweenTimestamps('SYSTIMESTAMP', 'last_activity')} > :idleMinutes)`,
    { idleMinutes: IDLE_TIMEOUT_MS / 60000 }
  );
  const count = r ? (r.rowsAffected || 0) : 0;
  if (count > 0) logger.info('Expired stale sessions', { count });
  return count;
}

// ── Delete old revoked/expired sessions (cleanup) ───────────────────
async function purgeOldSessions(olderThanDays) {
  if (!(await tableExists())) return 0;
  const days = olderThanDays || PURGE_RETENTION_DAYS;
  const r = await db.executeWithCommit(
    `DELETE FROM user_sessions
      WHERE status IN ('REVOKED', 'EXPIRED')
        AND NVL(revoked_at, session_expires_at) < SYSTIMESTAMP - :days`,
    { days }
  );
  const count = r ? (r.rowsAffected || 0) : 0;
  if (count > 0) logger.info('Purged old sessions', { count, days });
  return count;
}

// ── App-level cleanup scheduler ─────────────────────────────────────
let _cleanupInterval = null;
let _purgeInterval = null;
function startCleanupScheduler() {
  if (_cleanupInterval) return;

  const MS_PER_MINUTE = 60 * 1000;
  const MS_PER_DAY    = 86400 * 1000;

  // Expire idle sessions every 1 minute
  _cleanupInterval = setInterval(async () => {
    try { await cleanupExpiredSessions(); }
    catch(e) { logger.error('Session cleanup failed', { error: e.message }); }
  }, MS_PER_MINUTE);

  // Purge old revoked/expired rows daily
  _purgeInterval = setInterval(async () => {
    try { await purgeOldSessions(PURGE_RETENTION_DAYS); }
    catch(e) { logger.error('Session purge failed', { error: e.message }); }
  }, MS_PER_DAY);

  logger.info('Session cleanup scheduler started — expire every 1 min, purge daily');
}

module.exports = {
  hashRefreshToken,
  createSession,
  findSessionById,
  validateAndTouchSession,
  findSessionByTokenHash,
  rotateSession,
  revokeSession,
  expireSession,
  getActiveSessions,
  cleanupExpiredSessions,
  purgeOldSessions,
  startCleanupScheduler,
  fingerprintDevice,
  tableExists,
  SESSION_MAX_AGE_MS,
  IDLE_TIMEOUT_MS,
  TOUCH_THRESHOLD_MIN,
  REFRESH_COOKIE_NAME,
};
