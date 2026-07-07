'use strict';

const router     = require('express').Router();
const { verifyToken, requireAdmin } = require('../middleware/auth');
const adminCtrl  = require('../controllers/adminController');
const logger     = require('../config/logger');

// ── Auth (public) ─────────────────────────────────────────────────────
router.use('/auth', require('./auth'));

// ── All routes below require valid JWT ───────────────────────────────
router.use(verifyToken);

// ── Reference data — readable by ALL logged-in users ─────────────────
// These were previously admin-only, causing company/service dropdowns
// to be empty for non-admin users
router.get('/ref/groups',    adminCtrl.getGroups);
router.get('/ref/companies', adminCtrl.getCompanies);
router.get('/ref/services',  adminCtrl.getServices);
router.get('/ref/users',     adminCtrl.getUsers);
router.get('/ref/company-mapping', require('../controllers/adminController').getCompanyMappingRef);
router.get('/ref/company-services',  require('../controllers/adminController').getCompanyServicesRef);
router.get('/ref/modules',   require('../controllers/moduleController').getModulesRef);

// ── Core resources ────────────────────────────────────────────────────
router.use('/releases',      require('./releases'));
router.use('/task-list',     require('./taskList'));
router.use('/tasks',         require('./tasks'));
router.use('/notifications', require('./notifications'));
router.use('/audit',         require('./audit'));
router.use('/analytics',     require('./analytics'));

// ── Modules & Approvals ───────────────────────────────────────────────
router.use('/modules',   require('./modules'));
router.use('/approvals', require('./approvals'));

// ── Admin-only write operations ───────────────────────────────────────
router.use('/admin', requireAdmin, require('./admin'));

// ── ServiceNow admin endpoints (requireAdmin) ────────────────────────
router.use('/admin/servicenow', requireAdmin, require('./servicenow'));

// ── Test Email endpoint (temporary) ──────────────────────────────────
router.get('/test-email', async (req, res) => {
  try {
    const emailSvc = require('../services/emailService');
    const db = require('../config/db');
    const row = await db.queryOne("SELECT release_id FROM crms_releases WHERE is_deleted=0 ORDER BY release_id FETCH FIRST 1 ROWS ONLY", {});
    if (!row) return res.json({ success: false, error: 'No releases found to send a test email' });
    await emailSvc.sendPhaseStarted(String(parseInt(row.RELEASE_ID, 10) || 0), 'RD', req.user.userId);
    logger.info('[TestEmail] sent for release ' + row.RELEASE_ID);
    return res.json({ success: true });
  } catch (err) {
    logger.error('[TestEmail] failed', { error: err.message });
    return res.json({ success: false, error: err.message });
  }
});

module.exports = router;
