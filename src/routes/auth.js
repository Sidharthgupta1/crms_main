'use strict';
const router  = require('express').Router();
const rateLimit = require('express-rate-limit');
const ctrl    = require('../controllers/authController');
const ssoCtrl = require('../controllers/ssoController');
const { verifyToken, requireAdmin } = require('../middleware/auth');

// ── Rate limiters ───────────────────────────────────────────────────
const refreshLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 30,                  // 30 refresh attempts per window
  message: { error: 'Too many refresh attempts, please try again later' },
  standardHeaders: true,
  legacyHeaders: false,
});

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: parseInt(process.env.LOGIN_RATE_LIMIT, 10) || 20,
  message: { error: 'Too many login attempts, please try again later' },
  standardHeaders: true,
  legacyHeaders: false,
});

// ── Auth routes ──────────────────────────────────────────────────────
router.post('/login',              loginLimiter, ctrl.loginValidation, ctrl.login);
router.post('/refresh',            refreshLimiter, ctrl.refresh);
router.post('/logout',             verifyToken, ctrl.logout);
router.get ('/sessions',           verifyToken, ctrl.getSessions);
router.delete('/sessions/:sessionId', verifyToken, ctrl.deleteSession);
router.get ('/me',                 verifyToken, ctrl.me);
router.get ('/users',              ctrl.listUsers);

// FND Sync — Admin only
router.get ('/fnd-sync-status',    verifyToken, requireAdmin, ctrl.fndSyncStatus);
router.post('/fnd-sync-all',       verifyToken, requireAdmin, ctrl.fndSyncAll);
router.post('/fnd-provision-one',  verifyToken, requireAdmin, ctrl.fndProvisionOne);
router.patch('/crms-user/:userId', verifyToken, requireAdmin, ctrl.updateCrmsUser);

// SSO
router.post('/fnd-token',          ssoCtrl.createFndToken);
router.get ('/fnd-sso',            ssoCtrl.fndSso);
router.get ('/fnd-users',          verifyToken, ssoCtrl.listFndUsers);
router.post('/link-fnd-user',      verifyToken, ssoCtrl.linkFndUser);
router.get ('/ebs-launch',         ssoCtrl.ebsLaunch);
router.get ('/ebs-session-check',  ssoCtrl.ebsSessionCheck);

module.exports = router;
