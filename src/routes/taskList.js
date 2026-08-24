'use strict';
const router = require('express').Router();
const ctrl   = require('../controllers/taskListController');

router.get   ('/',       ctrl.getTaskList);
router.get   ('/live',   ctrl.getLiveTaskList);  // GET /task-list/live — live from DB
router.post  ('/save-manual',      ctrl.saveManual);      // POST /task-list/save-manual — all authenticated users
router.post  ('/save-manual-bulk', ctrl.saveManualBulk);  // POST /task-list/save-manual-bulk — all authenticated users
router.get   ('/can-edit', ctrl.canEdit);   // GET  /task-list

// Editor-only writes — the UI already gates these client-side, this enforces
// it server-side too so the check can't be bypassed by calling the API directly.
router.post  ('/',       ctrl.requireTaskListEditor, ctrl.createTask);    // POST /task-list
router.post  ('/bulk',   ctrl.requireTaskListEditor, ctrl.bulkUpsert);    // POST /task-list/bulk (save all)
router.delete('/bulk',   ctrl.requireTaskListEditor, ctrl.bulkDelete);    // DELETE /task-list/bulk (delete many)
router.patch ('/:id',    ctrl.requireTaskListEditor, ctrl.updateTask);    // PATCH /task-list/:id
router.delete('/:id',    ctrl.requireTaskListEditor, ctrl.deleteTask);    // DELETE /task-list/:id

module.exports = router;
