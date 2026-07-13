'use strict';

const jwt      = require('jsonwebtoken');
const db       = require('../config/db');
const logger   = require('../config/logger');
const session  = require('../services/sessionService');

// ── Clear refresh cookie (inline — avoids circular import with controller) ──
function clearRefreshCookie(res) {
  res.clearCookie(session.REFRESH_COOKIE_NAME, {
    httpOnly:  true,
    secure:    process.env.NODE_ENV === 'production',
    sameSite:  'lax',
    path:      '/',
  });
}

// ── verifyToken ──────────────────────────────────────────────────────
/**
 * Middleware: validates Bearer JWT, validates session state, attaches req.user.
 *
 * Session checks (in order):
 *   1. status must be ACTIVE
 *   2. session_expires_at must be in the future
 *   3. last_activity must be within idle timeout (30 min)
 *   4. last_activity is updated only if older than 5 min (throttled)
 */
async function verifyToken(req, res, next) {
  try {
    const authHeader = req.headers.authorization || '';
    if (!authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ success: false, error: 'No token provided', code: 'NO_TOKEN' });
    }

    const token   = authHeader.slice(7);
    const payload = jwt.verify(token, process.env.JWT_SECRET);

    const sessionId = payload.sid;

    // ── Session validation (if session_id present) ──────────────────
    if (sessionId) {
      try {
        // SELECT for validation + conditional UPDATE for touch (no duplicate queries)
        const result = await session.validateAndTouchSession(sessionId);

        if (!result.valid) {
          clearRefreshCookie(res);
          return res.status(401).json({
            success: false,
            error:   result.reason === 'IDLE_TIMEOUT'
                       ? 'Session expired due to inactivity'
                       : 'Session ' + result.reason.toLowerCase(),
            message: 'Your session has expired. Please sign in again.',
            code:    result.code,
          });
        }
      } catch (sessErr) {
        // Graceful degradation: if USER_SESSIONS table doesn't exist,
        // fall back to JWT-only validation so the app still works before migration
        const msg = (sessErr.message || '').toUpperCase();
        if (msg.includes('ORA-00942') || msg.includes('TABLE OR VIEW DOES NOT EXIST')) {
          logger.warn('USER_SESSIONS table not found — falling back to JWT-only auth');
        } else {
          logger.warn('Session validation skipped (will retry next request)', { error: sessErr.message });
        }
      }
    }

    // ── Verify user still exists and is active ──────────────────────
    const user = await db.queryOne(
      `SELECT u.user_id, u.initials, u.full_name, u.role, u.is_active
         FROM crms_users u
        WHERE u.user_id = :userId AND u.is_active = 1`,
      { userId: payload.sub }
    );

    if (!user) {
      return res.status(401).json({ success: false, error: 'User not found or deactivated', code: 'USER_INACTIVE' });
    }

    req.user = {
      userId:    user.USER_ID,
      initials:  user.INITIALS,
      fullName:  user.FULL_NAME,
      role:      user.ROLE,
      sessionId: sessionId || null,
    };

    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({ success: false, error: 'Token expired', code: 'TOKEN_EXPIRED' });
    }
    if (err.name === 'JsonWebTokenError') {
      return res.status(401).json({ success: false, error: 'Invalid token', code: 'INVALID_TOKEN' });
    }
    logger.error('verifyToken error', { err: err.message });
    return res.status(500).json({ success: false, error: 'Authentication error', code: 'AUTH_ERROR' });
  }
}

// ── requireAdmin ─────────────────────────────────────────────────────
function requireAdmin(req, res, next) {
  if (req.user && req.user.role === 'admin') return next();
  return res.status(403).json({ error: 'Admin access required' });
}

// ── requireOwnerOrAdmin ──────────────────────────────────────────────
function requireOwnerOrAdmin(paramName = 'userId') {
  return (req, res, next) => {
    const targetId = req.params[paramName];
    if (req.user.role === 'admin' || String(req.user.userId) === String(targetId)) {
      return next();
    }
    return res.status(403).json({ error: 'Forbidden' });
  };
}

module.exports = { verifyToken, requireAdmin, requireOwnerOrAdmin };
