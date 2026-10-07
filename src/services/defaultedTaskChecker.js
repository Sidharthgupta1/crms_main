'use strict';

// Periodically scans open sub-tasks for the "Default" threshold already
// used by the Resource Report (analyticsController.js: DEFAULT_THRESHOLD_DAYS)
// and emails the assignee once per task when it crosses that line.
// Dedup is done against crms_notifications (title='Task Defaulted: <taskNumber>')
// rather than a new DB column, so this needs no schema migration.

const db = require('../config/db');
const logger = require('../config/logger');

const DEFAULT_THRESHOLD_DAYS = 15;

function dayDiff(a, b) { return Math.floor((new Date(a) - new Date(b)) / 86400000); }

async function checkDefaultedTasks() {
  try {
    const rows = await db.query(
      "SELECT rt.task_id,rt.task_number,rt.phase_code,rt.short_description,rt.created_at,rt.assigned_to,rt.release_id "+
      "FROM crms_release_tasks rt "+
      "WHERE rt.assigned_to IS NOT NULL AND rt.state<>'Closed' "+
      "AND rt.created_at <= SYSDATE-"+DEFAULT_THRESHOLD_DAYS, {}
    );
    if (!rows.length) return;
    const emailSvc = require('./emailService');
    for (const r of rows) {
      const ageingDays = dayDiff(new Date(), r.CREATED_AT);
      try {
        await emailSvc.sendTaskDefaulted(
          Number(r.RELEASE_ID), Number(r.TASK_ID), r.TASK_NUMBER, r.PHASE_CODE, Number(r.ASSIGNED_TO), ageingDays, r.SHORT_DESCRIPTION
        );
      } catch (e) {
        logger.warn('[DefaultedTaskChecker] sendTaskDefaulted failed', { taskId: r.TASK_ID, error: e.message });
      }
    }
    logger.info('[DefaultedTaskChecker] scan complete', { candidates: rows.length });
  } catch (err) {
    logger.error('[DefaultedTaskChecker] scan failed', { error: err.message });
  }
}

function start() {
  const SIX_HOURS = 6 * 60 * 60 * 1000;
  setTimeout(() => checkDefaultedTasks().catch(() => {}), 60 * 1000);
  setInterval(() => checkDefaultedTasks().catch(() => {}), SIX_HOURS);
  logger.info('[DefaultedTaskChecker] scheduled every 6h (first run in 60s)');
}

module.exports = { start, checkDefaultedTasks };
