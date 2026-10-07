'use strict';
const router = require('express').Router();
const ctrl = require('../controllers/emailActionController');

// Deliberately public (mounted before the verifyToken gate in routes/index.js)
// — the token itself is the credential. See emailActionController.js.
router.get('/:token', ctrl.handleEmailAction);

module.exports = router;
