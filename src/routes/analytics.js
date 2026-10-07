'use strict';

const router = require('express').Router();
const ctrl   = require('../controllers/analyticsController');

router.get('/summary', ctrl.getSummary);

router.get('/subtask-assignees', ctrl.getSubtaskAssignees);

router.get('/resource-report', ctrl.getResourceReport);

router.get('/resource-bandwidth', ctrl.getResourceBandwidth);

module.exports = router;
