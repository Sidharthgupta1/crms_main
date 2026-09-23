'use strict';

const db = require('../config/db');

function num(n) { return String(parseInt(n,10)||0); }
function safe(s) { return String(s||'').replace(/'/g,"''"); }

async function getSummary(req, res, next) {
  try {
    const w = ['r.is_deleted=0'];
    if (req.query.assignmentGroupId) w.push('r.assignment_group_id='+num(req.query.assignmentGroupId));
    if (req.query.userId)            w.push('r.requested_by='+num(req.query.userId));
    if (req.query.priority)          w.push("r.priority='"+safe(req.query.priority)+"'");
    const WHERE = 'WHERE '+w.join(' AND ');

    const [summary, byState, byPriority, byGroup, byUser, taskCount] = await Promise.all([
      db.queryOne(
        "SELECT COUNT(*) AS total,"+
        "COUNT(CASE WHEN r.state NOT IN('Closed','Cancelled') THEN 1 END) AS open_count,"+
        "COUNT(CASE WHEN r.state='Closed' THEN 1 END) AS closed_count,"+
        "COUNT(CASE WHEN r.state='Cancelled' THEN 1 END) AS cancelled_count,"+
        "COUNT(CASE WHEN r.priority='1' THEN 1 END) AS critical_count "+
        "FROM crms_releases r "+WHERE, {}
      ),
      db.query(
        "SELECT r.state,COUNT(*) AS cnt FROM crms_releases r "+WHERE+
        " GROUP BY r.state ORDER BY MIN(CASE r.state "+
        "WHEN 'Draft' THEN 1 WHEN 'BRD Phase' THEN 2 WHEN 'FSD Phase' THEN 3 "+
        "WHEN 'Awaiting approval' THEN 4 WHEN 'On Hold' THEN 5 "+
        "WHEN 'Development Phase' THEN 6 WHEN 'Testing/QA' THEN 7 "+
        "WHEN 'UAT' THEN 8 WHEN 'Deployment' THEN 9 WHEN 'Closed' THEN 10 ELSE 11 END)", {}
      ),
      db.query(
        "SELECT r.priority,"+
        "CASE r.priority WHEN '1' THEN '1 - Critical' WHEN '2' THEN '2 - High' "+
        "WHEN '3' THEN '3 - Moderate' WHEN '4' THEN '4 - Low' END AS lbl,"+
        "COUNT(*) AS cnt FROM crms_releases r "+WHERE+" GROUP BY r.priority ORDER BY r.priority", {}
      ),
      db.query(
        "SELECT NVL(ag.group_name,'(Unassigned)') AS grp,COUNT(*) AS cnt "+
        "FROM crms_releases r LEFT JOIN crms_assignment_groups ag ON ag.group_id=r.assignment_group_id "+
        WHERE+" GROUP BY ag.group_name ORDER BY cnt DESC", {}
      ),
      db.query(
        "SELECT u.full_name AS uname,COUNT(*) AS cnt "+
        "FROM crms_releases r JOIN crms_users u ON u.user_id=r.requested_by "+
        WHERE+" GROUP BY u.full_name ORDER BY cnt DESC", {}
      ),
      db.queryOne(
        "SELECT COUNT(*) AS total FROM crms_tasks t JOIN crms_releases r ON r.release_id=t.release_id "+WHERE, {}
      ),
    ]);

    return res.json({
      summary:{ total:Number(summary.TOTAL), open:Number(summary.OPEN_COUNT), closed:Number(summary.CLOSED_COUNT), cancelled:Number(summary.CANCELLED_COUNT), critical:Number(summary.CRITICAL_COUNT), tasks:Number(taskCount.TOTAL) },
      byState:    byState.map(r=>({ state:r.STATE, count:Number(r.CNT) })),
      byPriority: byPriority.map(r=>({ priority:r.PRIORITY, label:r.LBL, count:Number(r.CNT) })),
      byGroup:    byGroup.map(r=>({ group:r.GRP, count:Number(r.CNT) })),
      byUser:     byUser.map(r=>({ user:r.UNAME, count:Number(r.CNT) })),
    });
  } catch(err) { next(err); }
}

// GET /analytics/subtask-assignees
// Returns task count grouped by assigned_to person, optionally filtered by group/user
async function getSubtaskAssignees(req, res, next) {
  try {
    const grpId  = req.query.assignmentGroupId ? parseInt(req.query.assignmentGroupId, 10) : null;
    const userId = req.query.userId            ? parseInt(req.query.userId, 10)            : null;

    let sql =
      'SELECT u.user_id, u.full_name AS assignee_name, COUNT(t.task_id) AS task_count ' +
      'FROM crms_release_tasks t ' +
      'JOIN crms_users u ON u.user_id = t.assigned_to ' +
      'JOIN crms_releases r ON r.release_id = t.release_id AND r.is_deleted = 0 ';

    if (grpId)  sql += 'AND r.assignment_group_id = ' + grpId + ' ';
    if (userId) sql += 'AND r.requested_by = ' + userId + ' ';

    sql += 'GROUP BY u.user_id, u.full_name ORDER BY task_count DESC FETCH FIRST 50 ROWS ONLY';

    const rows = await db.query(sql, {});
    return res.json({
      byAssignee: rows.map(function(r) {
        return {
          userId:       r.USER_ID,
          assigneeName: r.ASSIGNEE_NAME,
          taskCount:    Number(r.TASK_COUNT),
        };
      })
    });
  } catch(err) { next(err); }
}

// GET /analytics/resource-report
// Resource-level workload visibility for Management: who is actually
// HOLDING sub-tasks (assigned_to on crms_release_tasks) — deliberately not
// who raised the CR (requested_by), since a CR's requester and the people
// doing the work are usually different people. Returns, per resource:
//   - currentTasks: open sub-tasks, with Task Ageing (days since the
//     sub-task was created) and Phase Ageing (days since the parent CR's
//     most recent state change — same basis as Task List's Phase Ageing)
//   - completedLastMonth: sub-tasks closed in the last 30 days, with days-
//     to-close and a Default/Not-Default flag
//   - allTimeCompleted: total closed sub-tasks ever, for context
async function getResourceReport(req, res, next) {
  try {
    // Aging past this many days = "Default" (breached), at or under = "Non-Default".
    const DEFAULT_THRESHOLD_DAYS = 15;
    const moduleId = req.query.moduleId ? num(req.query.moduleId) : null;
    const company  = req.query.company ? safe(req.query.company) : null;
    const extraWhere = (moduleId ? " AND r.module_id="+moduleId : '') + (company ? " AND r.company='"+company+"'" : '');

    const [currentRows, completedRows, allTimeRows] = await Promise.all([
      db.query(
        "SELECT rt.task_id,rt.task_number,rt.phase_code,rt.state,rt.created_at,rt.planned_end_date,"+
        "rt.assigned_to,u.full_name AS resource_name,"+
        "r.release_id,r.release_number,r.title AS release_title,r.company,m.module_name,"+
        "(SELECT MAX(h.changed_at) FROM crms_release_history h WHERE h.release_id=r.release_id) AS phase_started_at "+
        "FROM crms_release_tasks rt "+
        "JOIN crms_users u ON u.user_id=rt.assigned_to "+
        "JOIN crms_releases r ON r.release_id=rt.release_id AND r.is_deleted=0 "+
        "LEFT JOIN crms_modules m ON m.module_id=r.module_id "+
        "WHERE rt.assigned_to IS NOT NULL AND rt.state<>'Closed'"+extraWhere+
        " ORDER BY rt.created_at DESC", {}
      ),
      db.query(
        "SELECT rt.task_id,rt.task_number,rt.phase_code,rt.created_at,rt.closed_at,rt.planned_end_date,"+
        "rt.assigned_to,u.full_name AS resource_name,"+
        "r.release_id,r.release_number,r.title AS release_title,r.company,m.module_name "+
        "FROM crms_release_tasks rt "+
        "JOIN crms_users u ON u.user_id=rt.assigned_to "+
        "JOIN crms_releases r ON r.release_id=rt.release_id AND r.is_deleted=0 "+
        "LEFT JOIN crms_modules m ON m.module_id=r.module_id "+
        "WHERE rt.assigned_to IS NOT NULL AND rt.state='Closed' AND rt.closed_at>=SYSDATE-30"+extraWhere+
        " ORDER BY rt.closed_at DESC", {}
      ),
      // Full all-time-completed list (not just a count) so the report can
      // list/export/link every closed sub-task ever, per resource.
      db.query(
        "SELECT rt.task_id,rt.task_number,rt.phase_code,rt.created_at,rt.closed_at,rt.planned_end_date,"+
        "rt.assigned_to,u.full_name AS resource_name,"+
        "r.release_id,r.release_number,r.title AS release_title,r.company,m.module_name "+
        "FROM crms_release_tasks rt "+
        "JOIN crms_users u ON u.user_id=rt.assigned_to "+
        "JOIN crms_releases r ON r.release_id=rt.release_id AND r.is_deleted=0 "+
        "LEFT JOIN crms_modules m ON m.module_id=r.module_id "+
        "WHERE rt.assigned_to IS NOT NULL AND rt.state='Closed'"+extraWhere+
        " ORDER BY rt.closed_at DESC", {}
      ),
    ]);

    function dayDiff(a, b) { return Math.floor((new Date(a) - new Date(b)) / 86400000); }

    // Ageing-matrix bucket: how many days a task is overdue against its
    // Planned End Date. <=0 is on-time/not-yet-due; the ranges above that
    // are the "0 / 1 to 3 / 4 to 20 / >20" buckets from the Resource Report
    // matrix. A task with no Planned End Date set can't be overdue, so it
    // falls into the "0" bucket.
    function ageingBucket(delayDays) {
      if (delayDays === null || delayDays === undefined || delayDays <= 0) return '0';
      if (delayDays <= 3)  return '1to3';
      if (delayDays <= 20) return '4to20';
      return 'gt20';
    }

    const currentTasks = currentRows.map(function(r){
      const reportedAt = r.CREATED_AT;
      const phaseStartedAt = r.PHASE_STARTED_AT || reportedAt;
      const plannedEndDate = r.PLANNED_END_DATE || null;
      const openDelayDays = plannedEndDate ? dayDiff(new Date(), plannedEndDate) : null;
      return {
        taskId: r.TASK_ID, taskNumber: r.TASK_NUMBER, phaseCode: r.PHASE_CODE, state: r.STATE,
        resourceUserId: num(r.ASSIGNED_TO), resourceName: r.RESOURCE_NAME,
        releaseId: r.RELEASE_ID, releaseNumber: r.RELEASE_NUMBER, releaseTitle: r.RELEASE_TITLE,
        company: r.COMPANY||'', moduleName: r.MODULE_NAME||'',
        reportedAt: reportedAt,
        taskAgeingDays: dayDiff(new Date(), reportedAt),
        phaseAgeingDays: dayDiff(new Date(), phaseStartedAt),
        plannedEndDate: plannedEndDate,
        openAgeingBucket: ageingBucket(openDelayDays),
      };
    });

    function mapCompleted(r) {
      const daysToClose = dayDiff(r.CLOSED_AT, r.CREATED_AT);
      const plannedEndDate = r.PLANNED_END_DATE || null;
      const closedDelayDays = plannedEndDate ? dayDiff(r.CLOSED_AT, plannedEndDate) : null;
      return {
        taskId: r.TASK_ID, taskNumber: r.TASK_NUMBER, phaseCode: r.PHASE_CODE,
        resourceUserId: num(r.ASSIGNED_TO), resourceName: r.RESOURCE_NAME,
        releaseId: r.RELEASE_ID, releaseNumber: r.RELEASE_NUMBER, releaseTitle: r.RELEASE_TITLE,
        company: r.COMPANY||'', moduleName: r.MODULE_NAME||'',
        reportedAt: r.CREATED_AT, closedAt: r.CLOSED_AT,
        daysToClose: daysToClose,
        isDefault: daysToClose > DEFAULT_THRESHOLD_DAYS,
        plannedEndDate: plannedEndDate,
        closedAgeingBucket: ageingBucket(closedDelayDays),
      };
    }
    const completedLastMonth = completedRows.map(mapCompleted);
    const allTimeCompleted   = allTimeRows.map(mapCompleted);

    const byResource = {};
    function ensureResource(uid, name) {
      if (!byResource[uid]) byResource[uid] = {
        userId: uid, name: name, currentCount: 0,
        completedLastMonthCount: 0, defaultCount: 0,
        allTimeCompleted: 0,
        openAgeing0: 0, openAgeing1to3: 0, openAgeing4to20: 0, openAgeingGt20: 0,
        closedAgeing0: 0, closedAgeing1to3: 0, closedAgeing4to20: 0, closedAgeingGt20: 0,
      };
      return byResource[uid];
    }
    var OPEN_BUCKET_FIELD   = { '0':'openAgeing0',   '1to3':'openAgeing1to3',   '4to20':'openAgeing4to20',   gt20:'openAgeingGt20' };
    var CLOSED_BUCKET_FIELD = { '0':'closedAgeing0', '1to3':'closedAgeing1to3', '4to20':'closedAgeing4to20', gt20:'closedAgeingGt20' };
    currentTasks.forEach(function(t){
      var s = ensureResource(t.resourceUserId, t.resourceName);
      s.currentCount++;
      s[OPEN_BUCKET_FIELD[t.openAgeingBucket]]++;
    });
    completedLastMonth.forEach(function(t){
      var s = ensureResource(t.resourceUserId, t.resourceName);
      s.completedLastMonthCount++;
      if (t.isDefault) s.defaultCount++;
      s[CLOSED_BUCKET_FIELD[t.closedAgeingBucket]]++;
    });
    allTimeCompleted.forEach(function(t){ ensureResource(t.resourceUserId, t.resourceName).allTimeCompleted++; });

    return res.json({
      defaultThresholdDays: DEFAULT_THRESHOLD_DAYS,
      resources: Object.values(byResource).sort(function(a,b){ return b.currentCount - a.currentCount; }),
      currentTasks: currentTasks,
      completedLastMonth: completedLastMonth,
      allTimeCompleted: allTimeCompleted,
    });
  } catch(err) { next(err); }
}

module.exports = { getSummary, getSubtaskAssignees, getResourceReport };
