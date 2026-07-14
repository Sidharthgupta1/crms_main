'use strict';

const bcrypt   = require('bcryptjs');
const jwt      = require('jsonwebtoken');
const { body } = require('express-validator');
const db       = require('../config/db');
const logger   = require('../config/logger');
const { validate } = require('../middleware/validate');
const session  = require('../services/sessionService');

function safe(s) { return String(s||'').replace(/'/g,"''"); }
function num(n)  { return String(parseInt(n,10)||0); }

// ── JWT signing functions (shared by auth + SSO) ────────────────────
function signAccess(userId, role, sessionId) {
  const payload = { sub: userId, role };
  if (sessionId) payload.sid = sessionId;
  return jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES_IN || '15m' });
}

function signRefresh(userId, sessionId) {
  const payload = { sub: userId, jti: require('crypto').randomUUID() };
  if (sessionId) payload.sid = sessionId;
  return jwt.sign(payload, process.env.JWT_REFRESH_SECRET, { expiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '8h' });
}

// ── Set refresh token cookie ────────────────────────────────────────
function setRefreshCookie(res, token) {
  res.cookie(session.REFRESH_COOKIE_NAME, token, {
    httpOnly:  true,
    secure:    process.env.NODE_ENV === 'production',
    sameSite:  'lax',
    maxAge:    session.SESSION_MAX_AGE_MS,
    path:      '/',
  });
}

// ── Clear refresh token cookie ──────────────────────────────────────
function clearRefreshCookie(res) {
  res.clearCookie(session.REFRESH_COOKIE_NAME, {
    httpOnly:  true,
    secure:    process.env.NODE_ENV === 'production',
    sameSite:  'lax',
    path:      '/',
  });
}

async function validateOracleCredentials(username, password) {
  try {
    const oracledb = db.oracledb;
    const result = await db.callFunction(
      'BEGIN :ret := FND_WEB_SEC.VALIDATE_LOGIN(:user, :pass); END;',
      {
        ret:  { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 10 },
        user: { dir: oracledb.BIND_IN,  val:  username },
        pass: { dir: oracledb.BIND_IN,  val:  password },
      }
    );
    const returnVal = (result.outBinds && result.outBinds.ret) || '';
    return { valid: returnVal === 'Y' };
  } catch(err) {
    const msg = err.message || '';
    if (msg.includes('ORA-04067') || msg.includes('not found'))
      return { valid: false, reason: 'oracle_api_unavailable' };
    if (msg.includes('ORA-28000') || msg.includes('account is locked'))
      return { valid: false, reason: 'account_locked', message: 'Your Oracle account is locked.' };
    if (msg.includes('ORA-01017'))
      return { valid: false, reason: 'invalid_credentials' };
    return { valid: false, reason: 'oracle_api_error', message: msg };
  }
}

function makeInitials(username) {
  const words = username.replace(/[._]/g, ' ').trim().split(/\s+/);
  let init = words.map(w => w.charAt(0)).join('').toUpperCase().slice(0, 3);
  if (!init) init = username.slice(0, 2).toUpperCase();
  return init;
}

function makeDisplayName(fndRow) {
  function cleanDesc(raw) {
    if (!raw) return '';
    return raw.replace(/[^a-zA-Z .'\-]/g, ' ').replace(/\s+/g, ' ').trim()
      .split(' ').filter(function(w) { return w.replace(/[^a-zA-Z]/g, '').length >= 2; })
      .map(function(w) { return w.charAt(0).toUpperCase() + w.slice(1).toLowerCase(); })
      .join(' ');
  }
  const desc = (fndRow.DESCRIPTION || '').trim();
  if (desc && desc.toUpperCase() !== (fndRow.USER_NAME || '').toUpperCase()) {
    const cleaned = cleanDesc(desc);
    if (cleaned && cleaned.length >= 2) return cleaned;
  }
  return (fndRow.USER_NAME || '').replace(/[._]/g, ' ').split(' ')
    .filter(function(w) { return w.length > 0; })
    .map(function(w) { return w.charAt(0).toUpperCase() + w.slice(1).toLowerCase(); })
    .join(' ');
}

async function findOrProvisionUser(username, fndRow) {
  let crmsUser = await db.queryOne(
    "SELECT user_id, initials, full_name, role, password_hash, is_active " +
    "FROM crms_users WHERE UPPER(fnd_user_name)='" + username + "' AND ROWNUM=1", {}
  );
  if (crmsUser) return { crmsUser, isNew: false };

  const fullName = makeDisplayName(fndRow);
  let   initials = makeInitials(username);
  let suffix = 0;
  while (true) {
    const clash = await db.queryOne(
      "SELECT user_id FROM crms_users WHERE UPPER(initials)='" + initials + "'", {}
    );
    if (!clash) break;
    suffix++;
    initials = makeInitials(username).slice(0, 2) + suffix;
  }

  const dummyHash = '$2b$12$invalidhash.placeholder.never.used.for.oracle.auth.mode';
  await db.executeWithCommit(
    "INSERT INTO crms_users(initials, full_name, role, password_hash, fnd_user_name, is_active, created_at) " +
    "VALUES('" + safe(initials) + "', '" + safe(fullName) + "', 'user', '" +
    safe(dummyHash) + "', '" + safe(username) + "', 1, SYSDATE)", {}
  );

  crmsUser = await db.queryOne(
    "SELECT user_id, initials, full_name, role, password_hash, is_active " +
    "FROM crms_users WHERE UPPER(fnd_user_name)='" + username + "' AND ROWNUM=1", {}
  );

  if (crmsUser) {
    await db.executeWithCommit(
      "INSERT INTO crms_audit(action, performed_by, cr_number, details) VALUES(" +
      "'User Auto-Provisioned', " + num(crmsUser.USER_ID) + ", '--', " +
      "'New Oracle user " + safe(username) + " auto-provisioned as " + safe(fullName) + "')", {}
    );
  }
  return { crmsUser, isNew: true };
}

// ── Login validation ────────────────────────────────────────────────
const loginValidation = [
  body('username').trim().notEmpty().withMessage('Username required'),
  body('password').notEmpty().withMessage('Password required'),
  body('database').optional().isIn(['PRIMARY', 'SECONDARY']).withMessage('database must be PRIMARY or SECONDARY'),
  validate,
];

async function login(req, res, next) {
  try {
    const database = (req.body.database || 'PRIMARY').toUpperCase();
    if (database === 'SECONDARY') return await loginWithSecondary(req, res);

    const username = (req.body.username || req.body.initials || '').toUpperCase();
    const password = req.body.password || '';

    const crmsUser = await db.queryOne(
      "SELECT user_id, initials, full_name, role, password_hash, is_active " +
      "FROM crms_users WHERE UPPER(initials)='" + safe(username) + "' AND ROWNUM=1", {}
    );

    if (!crmsUser) return res.status(401).json({ error: 'Invalid credentials.' });
    if (!crmsUser.IS_ACTIVE) return res.status(403).json({ error: 'Your account has been deactivated.' });

    const passwordMatch = await bcrypt.compare(password, crmsUser.PASSWORD_HASH);
    if (!passwordMatch) return res.status(401).json({ error: 'Invalid credentials.' });

    await db.executeWithCommit(
      "UPDATE crms_users SET instance='PRIMARY' WHERE UPPER(initials)='" + safe(username) + "'", {}
    );

    return await issueTokens(res, crmsUser, false, req);

  } catch (err) { next(err); }
}

async function loginWithSecondary(req, res) {
  const initials = (req.body.username || req.body.initials || '').toUpperCase();
  const password = req.body.password || '';

  if (!db.isSecondaryReady()) {
    return res.status(503).json({ error: 'Secondary database is not configured.' });
  }

  let secUser;
  try {
    secUser = await db.queryOneSecondary(
      "SELECT user_id, initials, full_name, role, password_hash, is_active, " +
      "email_address, refresh_token_hash, last_login, created_at " +
      "FROM crms_users WHERE UPPER(initials)='" + safe(initials) + "' AND ROWNUM=1", {}
    );
  } catch (err) {
    return res.status(503).json({ error: 'Could not query secondary database.', detail: err.message });
  }

  if (!secUser) return res.status(401).json({ error: 'Invalid credentials.' });
  if (!secUser.IS_ACTIVE) return res.status(403).json({ error: 'Your account has been deactivated.' });

  const passwordMatch = await bcrypt.compare(password, secUser.PASSWORD_HASH);
  if (!passwordMatch) return res.status(401).json({ error: 'Invalid credentials.' });

  let primaryUser;
  try { primaryUser = await syncSecondaryUser(secUser); }
  catch (err) { return res.status(500).json({ error: 'Failed to sync user to primary.', detail: err.message }); }

  return await issueTokens(res, primaryUser, primaryUser._isNew, req);
}

async function syncSecondaryUser(secUser) {
  const initials = (secUser.INITIALS || '').toUpperCase();
  if (!initials) throw new Error('Cannot sync secondary user without initials');

  let primaryUser = await db.queryOne(
    "SELECT user_id, initials, full_name, role, password_hash, is_active " +
    "FROM crms_users WHERE UPPER(initials)='" + safe(initials) + "' AND ROWNUM=1", {}
  );

  if (primaryUser) {
    await db.executeWithCommit(
      "UPDATE crms_users SET instance='SECONDARY' WHERE UPPER(initials)='" + safe(initials) + "'", {}
    );
    primaryUser._isNew = false;
    return primaryUser;
  }

  const rawRole = (secUser.ROLE || 'user').toLowerCase();
  const role = (rawRole === 'admin') ? 'admin' : 'user';
  const displayName = secUser.FULL_NAME || initials;
  const lastLog = (secUser.LAST_LOGIN instanceof Date) ? secUser.LAST_LOGIN : new Date();
  const created = (secUser.CREATED_AT instanceof Date) ? secUser.CREATED_AT : new Date();

  await db.executeWithCommit(
    "INSERT INTO crms_users(initials, full_name, role, password_hash, is_active, " +
    "email_address, instance, last_login, created_at) " +
    "VALUES('" + safe(initials) + "', '" + safe(displayName) + "', '" + safe(role) + "', " +
    "'" + safe(secUser.PASSWORD_HASH || '') + "', " +
    (secUser.IS_ACTIVE == null || secUser.IS_ACTIVE === 1 ? 1 : 0) + ", " +
    "'" + safe(secUser.EMAIL_ADDRESS || '') + "', 'SECONDARY', :lastLogin, :createdAt)",
    { lastLogin: lastLog, createdAt: created }
  );

  primaryUser = await db.queryOne(
    "SELECT user_id, initials, full_name, role, password_hash, is_active " +
    "FROM crms_users WHERE UPPER(initials)='" + safe(initials) + "' AND ROWNUM=1", {}
  );

  if (primaryUser) {
    await db.executeWithCommit(
      "INSERT INTO crms_audit(action, performed_by, cr_number, details) VALUES(" +
      "'User Synced from Secondary DB', " + num(primaryUser.USER_ID) + ", '--', " +
      "'Secondary DB user " + safe(initials) + " synced as " + safe(displayName) + "')", {}
    );
    primaryUser._isNew = true;
  }
  return primaryUser;
}

// ── Issue tokens + create session (CORRECT FLOW) ───────────────────
async function issueTokens(res, crmsUser, isNew, req) {
  const userId = num(crmsUser.USER_ID);

  await db.executeWithCommit(
    "UPDATE crms_users SET last_login=SYSDATE WHERE user_id=" + userId, {}
  );
  await db.executeWithCommit(
    "INSERT INTO crms_audit(action, performed_by, cr_number, details) VALUES(" +
    "'Login', " + userId + ", '--', '" + safe(crmsUser.FULL_NAME) + " logged in (Oracle auth)')", {}
  );

  // STEP 1: Create session FIRST to obtain session_id
  const sess = await session.createSession(crmsUser.USER_ID, null, req);
  const sessionId = sess.sessionId;

  // STEP 2: Generate tokens WITH session_id
  const accessToken  = signAccess(crmsUser.USER_ID, crmsUser.ROLE, sessionId);
  const refreshToken = signRefresh(crmsUser.USER_ID, sessionId);

  // STEP 3: Hash refresh token and update session row
  await session.rotateSession(sessionId, refreshToken);

  // STEP 4: Set refresh token as HttpOnly cookie
  setRefreshCookie(res, refreshToken);

  logger.info('Login success', { userId, username: crmsUser.INITIALS, isNew, sessionId });

  return res.json({
    accessToken,
    sessionId,
    isNewUser: isNew,
    user: {
      userId:   crmsUser.USER_ID,
      initials: crmsUser.INITIALS,
      fullName: crmsUser.FULL_NAME,
      role:     crmsUser.ROLE,
    },
  });
}

// ── Refresh: read cookie, rotate, return new access token ───────────
async function refresh(req, res, next) {
  try {
    const token = req.cookies && req.cookies[session.REFRESH_COOKIE_NAME];
    if (!token) return res.status(401).json({ success: false, error: 'No refresh token', code: 'NO_REFRESH_TOKEN' });

    // STEP 1: Verify JWT signature
    let payload;
    try { payload = jwt.verify(token, process.env.JWT_REFRESH_SECRET); }
    catch(e) {
      clearRefreshCookie(res);
      return res.status(401).json({ success: false, error: 'Invalid or expired refresh token', code: 'INVALID_REFRESH_TOKEN' });
    }

    // STEP 2: Extract session_id from JWT
    const sessionId = payload.sid;

    // STEP 3: Session-based validation (if table exists and sessionId present)
    if (sessionId && await session.tableExists()) {
      const sess = await session.findSessionById(sessionId);
      if (!sess) return res.status(401).json({ success: false, error: 'Session not found', code: 'SESSION_NOT_FOUND' });

      // Verify presented token matches stored hash
      const tokenHash = session.hashRefreshToken(token);
      if (sess.REFRESH_TOKEN_HASH !== tokenHash) {
        await session.expireSession(sessionId);
        return res.status(401).json({ success: false, error: 'Refresh token reuse detected', code: 'INVALID_REFRESH_TOKEN' });
      }

      if (sess.STATUS !== 'ACTIVE') {
        clearRefreshCookie(res);
        return res.status(401).json({ success: false, error: 'Session is ' + sess.STATUS.toLowerCase(), message: 'Your session is no longer valid. Please sign in again.', code: 'SESSION_' + sess.STATUS });
      }

      if (new Date(sess.SESSION_EXPIRES_AT) < new Date()) {
        await session.expireSession(sessionId);
        clearRefreshCookie(res);
        return res.status(401).json({ success: false, error: 'Session expired', message: 'Your session has expired. Please sign in again.', code: 'SESSION_EXPIRED' });
      }

      const lastActivity = new Date(sess.LAST_ACTIVITY);
      const idleMs = Date.now() - lastActivity.getTime();
      if (idleMs > session.IDLE_TIMEOUT_MS) {
        await session.expireSession(sessionId);
        clearRefreshCookie(res);
        return res.status(401).json({ success: false, error: 'Session expired due to inactivity', message: 'Your session has expired due to inactivity. Please sign in again.', code: 'SESSION_IDLE_TIMEOUT' });
      }
    }

    // STEP 4: Verify user still active
    const user = await db.queryOne(
      "SELECT user_id, role, is_active FROM crms_users WHERE user_id=" + num(payload.sub), {}
    );
    if (!user || !user.IS_ACTIVE) {
      if (sessionId) await session.expireSession(sessionId);
      clearRefreshCookie(res);
      return res.status(401).json({ success: false, error: 'User not found or inactive', code: 'SESSION_INVALID' });
    }

    // STEP 5: Generate new tokens
    const newAccessToken  = signAccess(user.USER_ID, user.ROLE, sessionId);
    const newRefreshToken = signRefresh(user.USER_ID, sessionId);

    // STEP 6: Rotate session hash (if session exists)
    if (sessionId && await session.tableExists()) {
      await session.rotateSession(sessionId, newRefreshToken);
    }

    // STEP 7: Set new refresh cookie
    setRefreshCookie(res, newRefreshToken);

    return res.json({ accessToken: newAccessToken });

  } catch(err) { next(err); }
}

// ── Logout: revoke current session, clear cookie ────────────────────
async function logout(req, res, next) {
  try {
    const uid = num(req.user.userId);
    const sessionId = req.user.sessionId;

    logger.info('Logout requested', { userId: uid, sessionId, fullName: req.user.fullName });

    // Revoke current session via session_id from JWT
    if (sessionId) {
      const rowsAffected = await session.revokeSession(sessionId);
      logger.info('Session revoke result', { sessionId, rowsAffected });
    } else {
      logger.warn('Logout: no sessionId in req.user — session not revoked', { userId: uid });
    }

    clearRefreshCookie(res);

    await db.executeWithCommit(
      "INSERT INTO crms_audit(action, performed_by, cr_number, details) VALUES(" +
      "'Logout', " + uid + ", '--', '" + safe(req.user.fullName) + " logged out')", {}
    );

    logger.info('Logout completed', { userId: uid, sessionId });
    return res.json({ message: 'Logged out' });
  } catch(err) { next(err); }
}

// ── Get active sessions ─────────────────────────────────────────────
async function getSessions(req, res, next) {
  try {
    const sessions = await session.getActiveSessions(req.user.userId);

    const result = sessions.map(s => ({
      SESSION_ID:        s.SESSION_ID,
      BROWSER:          s.BROWSER,
      OPERATING_SYSTEM:  s.OPERATING_SYSTEM,
      DEVICE_NAME:       s.DEVICE_NAME,
      IP_ADDRESS:        s.IP_ADDRESS,
      CREATED_AT:        s.CREATED_AT,
      LAST_ACTIVITY:     s.LAST_ACTIVITY,
      SESSION_EXPIRES_AT: s.SESSION_EXPIRES_AT,
      STATUS:            s.STATUS,
      USER_AGENT:        s.USER_AGENT,
      IS_CURRENT:        req.user.sessionId && s.SESSION_ID === req.user.sessionId,
    }));

    return res.json({ sessions: result });
  } catch(err) { next(err); }
}

// ── Delete a specific session ───────────────────────────────────────
async function deleteSession(req, res, next) {
  try {
    const targetSessionId = parseInt(req.params.sessionId, 10);
    if (!targetSessionId) return res.status(400).json({ error: 'Invalid session ID' });

    await session.revokeSession(targetSessionId);

    // If user revoked their own current session, clear the cookie
    if (req.user.sessionId && req.user.sessionId === targetSessionId) {
      clearRefreshCookie(res);
    }

    await db.executeWithCommit(
      "INSERT INTO crms_audit(action, performed_by, cr_number, details) VALUES(" +
      "'Session Revoked', " + num(req.user.userId) + ", '--', 'Session " + targetSessionId + " revoked')", {}
    );

    return res.json({ message: 'Session revoked' });
  } catch(err) { next(err); }
}

async function me(req, res, next) {
  try {
    const uid  = num(req.user.userId);
    const user = await db.queryOne(
      "SELECT u.user_id, u.initials, u.full_name, u.role, u.last_login, " +
      "LISTAGG(ag.group_name, ',') WITHIN GROUP (ORDER BY ag.group_name) AS groups " +
      "FROM crms_users u " +
      "LEFT JOIN crms_group_members gm ON gm.user_id = u.user_id " +
      "LEFT JOIN crms_assignment_groups ag ON ag.group_id = gm.group_id " +
      "WHERE u.user_id=" + uid +
      " GROUP BY u.user_id, u.initials, u.full_name, u.role, u.last_login", {}
    );
    if (!user) return res.status(404).json({ error: 'User not found' });
    return res.json({
      userId:      user.USER_ID,
      initials:    user.INITIALS,
      fullName:    user.FULL_NAME,
      role:        user.ROLE,
      groups:      user.GROUPS ? user.GROUPS.split(',') : [],
      lastLogin:   user.LAST_LOGIN,
    });
  } catch(err) { next(err); }
}

let _usersCache = null, _usersCacheTs = 0;
const USERS_CACHE_TTL = 60000;

async function listUsers(req, res, next) {
  if (_usersCache && (Date.now() - _usersCacheTs) < USERS_CACHE_TTL) {
    res.set('Cache-Control', 'public, max-age=60');
    return res.json(_usersCache);
  }
  try {
    const rows = await db.query(
      "SELECT initials, full_name FROM crms_users WHERE is_active=1 ORDER BY full_name", {}
    );
    _usersCache   = rows.map(r => ({ initials: r.INITIALS, fullName: r.FULL_NAME }));
    _usersCacheTs = Date.now();
    res.set('Cache-Control', 'public, max-age=60');
    return res.json(_usersCache);
  } catch(err) {
    return res.json(_usersCache || []);
  }
}

async function fndSyncStatus(req, res, next) {
  try {
    const pageSize = parseInt(process.env.ORACLE_USER_PAGE_SIZE, 10) || 2000;
    let totalCount = 0;
    try {
      const cntRow = await db.queryOne(
        "SELECT COUNT(*) AS cnt FROM fnd_user " +
        "WHERE NVL(end_date, SYSDATE+1) > SYSDATE " +
        "AND user_name NOT IN ('GUEST','INITIAL SETUP','SYSADMIN','ANONYMOUS')", {}
      );
      totalCount = Number(cntRow && cntRow.CNT) || 0;
    } catch(e) {}

    const rows = await db.query(
      "SELECT f.user_name AS fnd_user_name, f.description AS fnd_description, f.email_address AS email, " +
      "c.user_id AS crms_user_id, c.full_name AS crms_full_name, c.initials AS crms_initials, " +
      "c.role AS crms_role, c.is_active AS crms_is_active, c.last_login AS last_login " +
      "FROM fnd_user f LEFT JOIN crms_users c ON UPPER(c.fnd_user_name) = UPPER(f.user_name) " +
      "WHERE NVL(f.end_date, SYSDATE+1) > SYSDATE " +
      "AND f.user_name NOT IN ('GUEST','INITIAL SETUP','SYSADMIN','ANONYMOUS') " +
      "ORDER BY CASE WHEN c.user_id IS NULL THEN 0 ELSE 1 END, f.user_name " +
      "FETCH FIRST " + pageSize + " ROWS ONLY", {}
    );

    const data = rows.map(r => ({
      fndUserName:  r.FND_USER_NAME,
      description:  r.FND_DESCRIPTION || '',
      email:        r.EMAIL || '',
      crmsUserId:   r.CRMS_USER_ID || null,
      crmsFullName: r.CRMS_FULL_NAME || null,
      crmsInitials: r.CRMS_INITIALS || null,
      crmsRole:     r.CRMS_ROLE || null,
      crmsIsActive: r.CRMS_IS_ACTIVE != null ? (r.CRMS_IS_ACTIVE == 1) : null,
      lastLogin:    r.LAST_LOGIN || null,
      isSynced:     !!r.CRMS_USER_ID,
    }));

    return res.json({ users: data, totalCount, fetched: data.length, pageSize, truncated: totalCount > data.length });
  } catch(err) { next(err); }
}

async function fndSyncAll(req, res, next) {
  try {
    const fndUsers = await db.query(
      "SELECT user_name, description FROM fnd_user " +
      "WHERE NVL(end_date, SYSDATE+1) > SYSDATE " +
      "AND user_name NOT IN ('GUEST','INITIAL SETUP','SYSADMIN','ANONYMOUS') " +
      "AND NOT EXISTS (SELECT 1 FROM crms_users c WHERE UPPER(c.fnd_user_name)=UPPER(user_name)) " +
      "ORDER BY user_name FETCH FIRST 200 ROWS ONLY", {}
    );
    let created = 0, skipped = 0;
    for (const fnd of fndUsers) {
      try {
        await findOrProvisionUser(fnd.USER_NAME.toUpperCase(), { USER_NAME: fnd.USER_NAME, DESCRIPTION: fnd.DESCRIPTION });
        created++;
      } catch(e) { skipped++; }
    }
    bustUsersCache();
    return res.json({ message: 'Sync complete', created, skipped, total: fndUsers.length });
  } catch(err) { next(err); }
}

async function updateCrmsUser(req, res, next) {
  try {
    const targetId = num(req.params.userId);
    const { isActive, role, resetPassword } = req.body;
    const parts = [];
    if (isActive !== undefined) parts.push('is_active=' + (isActive ? 1 : 0));
    if (role && ['admin','user'].includes(role)) parts.push("role='" + role + "'");
    if (resetPassword === true)
      parts.push("password_hash='$2b$12$LO5bMX/h05wgtgsaOEOTWOEBYVoR6gONZTGjZm/.En4OdseFlok3u'");
    if (!parts.length) return res.status(422).json({ error: 'Nothing to update' });
    await db.executeWithCommit("UPDATE crms_users SET " + parts.join(',') + " WHERE user_id=" + targetId, {});
    const action = resetPassword ? 'Password Reset by Admin' :
      isActive === false ? 'User Deactivated' : isActive === true ? 'User Activated' : 'User Updated';
    await db.executeWithCommit(
      "INSERT INTO crms_audit(action, performed_by, cr_number, details) VALUES('" +
      action + "', " + num(req.user.userId) + ", '--', 'Admin updated user_id=" + targetId + "')", {}
    );
    bustUsersCache();
    return res.json({ message: 'User updated successfully' });
  } catch(err) { next(err); }
}

function bustUsersCache() { _usersCache = null; _usersCacheTs = 0; }

async function fndProvisionOne(req, res, next) {
  try {
    const { fndUserName } = req.body;
    if (!fndUserName) return res.status(400).json({ error: 'fndUserName required' });
    const uname = fndUserName.trim().toUpperCase();
    const fndRow = await db.queryOne(
      "SELECT user_id, user_name, description FROM fnd_user " +
      "WHERE UPPER(user_name)='" + safe(uname) + "' AND NVL(end_date, SYSDATE+1) > SYSDATE AND ROWNUM=1", {}
    );
    if (!fndRow) return res.status(404).json({ error: 'Oracle user not found: ' + uname });
    const { crmsUser, isNew } = await findOrProvisionUser(uname, fndRow);
    bustUsersCache();
    return res.json({
      message: isNew ? 'User provisioned successfully' : 'User already exists in CRMS',
      isNew, crmsUserId: crmsUser ? crmsUser.USER_ID : null, fullName: crmsUser ? crmsUser.FULL_NAME : null,
    });
  } catch(err) { next(err); }
}

// Start cleanup scheduler on module load
session.startCleanupScheduler();

module.exports = {
  loginValidation, login,
  refresh, logout, getSessions, deleteSession,
  me, listUsers, bustUsersCache,
  fndSyncStatus, fndSyncAll, fndProvisionOne, updateCrmsUser,
  signAccess, signRefresh,
  setRefreshCookie, clearRefreshCookie,
};
