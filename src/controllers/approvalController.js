'use strict';

const db     = require('../config/db');
const logger = require('../config/logger');
const flowQ  = require('../utils/approvalFlowQueries');

function safe(s) { return String(s||'').replace(/'/g,"''"); }
function num(n)  { return String(parseInt(n,10)||0); }

const AFTER_APPROVAL = {
  'DRAFT':      'RD Phase',
  'RD':         'FSD Phase',
  'FSD':        'Development Phase',
  'DEPLOYMENT': 'Closed',
};

// ── triggerApproval ───────────────────────────────────────────────────
// Called when a phase is ready for approval
// Returns { newState, approverName } or { autoApproved:true } or { error }
async function triggerApproval(releaseId, relNum, requestedBy, modId, phaseCode, selectedApproverId) {
  const rid   = num(releaseId);
  const reqBy = num(requestedBy);

  const relInfo = await db.queryOne(
    'SELECT module_id,current_approval_level FROM crms_releases WHERE release_id='+rid, {}
  ).catch(function(){ return null; });

  const mid      = relInfo && relInfo.MODULE_ID ? num(String(relInfo.MODULE_ID)) : num(String(modId||0));
  const curLevel = relInfo ? (Number(relInfo.CURRENT_APPROVAL_LEVEL)||0) : 0;

  // Always use crms_approval_flows (Module Mapping) — single source of truth
  const afterState = AFTER_APPROVAL[phaseCode];
  const fromState  = phaseCodeToState(phaseCode);

  if (!mid) {
    // No module assigned — auto-approve
    if (!afterState) return { autoApproved:true, reason:'no_module' };
    await db.executeWithCommit("UPDATE crms_releases SET state='"+safe(afterState)+"',current_approval_level=0,updated_at=SYSDATE WHERE release_id="+rid, {});
    await db.executeWithCommit("INSERT INTO crms_release_history(release_id,action,from_state,to_state,changed_by) VALUES("+rid+",'State Change','"+safe(fromState)+"','"+safe(afterState)+"',"+reqBy+")", {});
    return { autoApproved:true, reason:'no_module', newState:afterState };
  }

  // Get ALL approvers for this phase (mapping table + legacy fallback)
  const flowRows = await flowQ.queryPhaseApprovers(mid, phaseCode);

  const level1Rows = flowRows.filter(function(r) { return Number(r.LEVEL_ORDER) === 1; });

  // Auto-approve if no approvers configured
  if (!flowRows.length) {
    if (!afterState) return { autoApproved:true, reason:'no_flow' };
    await db.executeWithCommit("UPDATE crms_releases SET state='"+safe(afterState)+"',current_approval_level=0,updated_at=SYSDATE WHERE release_id="+rid, {});
    await db.executeWithCommit("INSERT INTO crms_release_history(release_id,action,from_state,to_state,changed_by) VALUES("+rid+",'State Change','"+safe(fromState)+"','"+safe(afterState)+"',"+reqBy+")", {});
    return { autoApproved:true, reason:'no_approver_flow', newState:afterState };
  }

  // Determine display name for requester notification (selected or all L1 approvers)
  let approverName = '';
  if (selectedApproverId) {
    const match = level1Rows.find(function(r) {
      return num(r.APPROVER_USER_ID) === num(selectedApproverId);
    });
    if (match) approverName = match.FULL_NAME;
  }
  if (!approverName && level1Rows.length) {
    approverName = level1Rows.map(function(r) { return r.FULL_NAME; }).join(', ');
  }

  // Build state name
  const phasePrefix = { RD:'RD', FSD:'FSD', DEV:'Development', TESTING:'Testing', UAT:'UAT', DEPLOYMENT:'Deployment' };
  const prefix   = phasePrefix[phaseCode] || phaseCode;
  const newState = phaseCode === 'DEPLOYMENT'
    ? 'Deployment Approval L1'
    : prefix + ' Awaiting Approval L1';

  // Record in crms_release_approvals — one pending row per approver at every level
  await db.executeWithCommit("DELETE FROM crms_release_approvals WHERE release_id="+rid+" AND phase_code='"+phaseCode+"'", {});
  for (const row of flowRows) {
    const auid = num(row.APPROVER_USER_ID);
    const lvl  = num(row.LEVEL_ORDER);
    await db.executeWithCommit(
      "INSERT INTO crms_release_approvals(release_id,module_id,phase_code,level_order,approver_user_id,status) "+
      "VALUES("+rid+","+mid+",'"+phaseCode+"',"+lvl+","+auid+",'Pending')", {}
    );
  }

  await db.executeWithCommit("UPDATE crms_releases SET state='"+safe(newState)+"',current_approval_level=1,updated_at=SYSDATE WHERE release_id="+rid, {});
  await db.executeWithCommit("INSERT INTO crms_release_history(release_id,action,from_state,to_state,changed_by) VALUES("+rid+",'State Change','"+safe(fromState)+"','"+safe(newState)+"',"+reqBy+")", {});

  // Notify every Level 1 approver
  for (const row of level1Rows) {
    const notifyUid = num(row.APPROVER_USER_ID);
    if (!notifyUid || notifyUid === '0') continue;
    await db.executeWithCommit(
      "INSERT INTO crms_notifications(user_id,title,message,release_id) VALUES("+
      notifyUid+",'Approval Required — "+phaseCode+" L1','"+
      safe(relNum+' requires your '+phaseCode+' Level 1 approval')+"',"+rid+")"
    ).catch(function(){});
  }

  // Notify requester
  if (reqBy) {
    await db.executeWithCommit(
      "INSERT INTO crms_notifications(user_id,title,message,release_id) VALUES("+
      reqBy+",'Pending "+phaseCode+" Approval','"+
      safe(relNum+' pending '+phaseCode+' L1 approval with '+approverName)+"',"+rid+")"
    ).catch(function(){});
  }

  logger.info('Approval triggered', { releaseId:rid, phaseCode, level:1, approverName });
  return { newState, approverName, levelOrder:1, flowType:phaseCode };
}
// Ensure pending approval rows exist for every mapped approver at this level
async function ensureLevelApprovalRecords(rid, mid, phaseCode, curLevel) {
  const flowRows = await flowQ.queryLevelApprovers(mid, phaseCode, curLevel);

  for (const row of flowRows) {
    const auid = num(row.APPROVER_USER_ID);
    if (!auid || auid === '0') continue;

    const existing = await db.queryOne(
      "SELECT approval_id FROM crms_release_approvals "+
      "WHERE release_id="+rid+" AND phase_code='"+phaseCode+"' AND level_order="+curLevel+
      " AND approver_user_id="+auid, {}
    ).catch(function(){ return null; });

    if (!existing) {
      await db.executeWithCommit(
        "INSERT INTO crms_release_approvals(release_id,module_id,phase_code,level_order,approver_user_id,status) "+
        "VALUES("+rid+","+mid+",'"+phaseCode+"',"+curLevel+","+auid+",'Pending')", {}
      );
    }
  }
}

// ── POST /releases/:releaseId/approve ────────────────────────────────
async function approve(req, res, next) {
  try {
    const rid      = num(req.params.releaseId);
    const uid      = num(req.user.userId);
    const comments = (req.body.comments||'').trim();

    const release = await db.queryOne(
      'SELECT release_id,state,release_number,module_id,current_approval_level,requested_by '+
      'FROM crms_releases WHERE release_id='+rid+' AND is_deleted=0', {}
    );
    if (!release) return res.status(404).json({ error:'Release not found' });

    const curState  = release.STATE;
    const curLevel  = Number(release.CURRENT_APPROVAL_LEVEL);
    const relNum    = release.RELEASE_NUMBER;
    const reqUserId = num(release.REQUESTED_BY);
    const mid       = num(String(release.MODULE_ID));

    // Determine phase from state name
    const phaseCode = stateToApprovalPhase(curState);
    if (!phaseCode)
      return res.status(400).json({ error:'Release is not in an approval state: '+curState });

    await ensureLevelApprovalRecords(rid, mid, phaseCode, curLevel);

    // Verify this user is the pending approver
    const myApproval = await db.queryOne(
      "SELECT approval_id FROM crms_release_approvals "+
      "WHERE release_id="+rid+" AND level_order="+curLevel+
      " AND approver_user_id="+uid+" AND status='Pending' AND phase_code='"+phaseCode+"'", {}
    );
    if (!myApproval)
      return res.status(403).json({ error:'You are not the approver for this level, or it has already been actioned.' });

    // Mark this level approved; skip other pending approvers at same level
    await db.executeWithCommit(
      "UPDATE crms_release_approvals SET status='Approved',comments='"+safe(comments)+"',actioned_at=SYSDATE "+
      "WHERE approval_id="+num(myApproval.APPROVAL_ID), {}
    );
    await db.executeWithCommit(
      "UPDATE crms_release_approvals SET status='Skipped',actioned_at=SYSDATE "+
      "WHERE release_id="+rid+" AND phase_code='"+phaseCode+"' AND level_order="+curLevel+
      " AND status='Pending' AND approver_user_id<>"+uid, {}
    );
    await db.executeWithCommit(
      "INSERT INTO crms_audit(action,performed_by,cr_number,details) VALUES("+
      "'Approval',"+uid+",'"+relNum+"','"+phaseCode+" Level "+curLevel+" approved by "+safe(req.user.fullName)+"')", {}
    );

    // Check next level
    const nextLevel = curLevel + 1;
    const hasNext   = await flowQ.hasFlowLevel(mid, phaseCode, nextLevel);
    const nextApprovers = hasNext
      ? await flowQ.queryLevelApprovers(mid, phaseCode, nextLevel)
      : [];

    let newState, message;

    if (hasNext) {
      // More levels remaining
      var pp = { DRAFT:'Draft', RD:'RD', FSD:'FSD', DEPLOYMENT:'Deployment' };
      newState = phaseCode === 'DEPLOYMENT'
        ? 'Deployment Approval L' + nextLevel
        : (pp[phaseCode]||phaseCode) + ' Awaiting Approval L' + nextLevel;

      await db.executeWithCommit(
        "UPDATE crms_releases SET state='"+safe(newState)+"',current_approval_level="+nextLevel+",updated_at=SYSDATE WHERE release_id="+rid, {}
      );
      await db.executeWithCommit(
        "INSERT INTO crms_release_history(release_id,action,from_state,to_state,changed_by) "+
        "VALUES("+rid+",'State Change','"+safe(curState)+"','"+safe(newState)+"',"+uid+")", {}
      );

      const nextNames = nextApprovers.map(function(r) { return r.FULL_NAME; }).join(', ') || 'Approver';

      for (const apr of nextApprovers) {
        const nextAprUid = num(apr.APPROVER_USER_ID);
        if (!nextAprUid || nextAprUid === '0') continue;
        await db.executeWithCommit(
          "INSERT INTO crms_notifications(user_id,title,message,release_id) VALUES("+
          nextAprUid+",'Approval Required — "+phaseCode+"','"+
          safe(relNum+' requires your '+phaseCode+' approval (Level '+nextLevel+')')+"',"+rid+")", {}
        );
      }
      await db.executeWithCommit(
        "INSERT INTO crms_notifications(user_id,title,message,release_id) VALUES("+
        reqUserId+",'Approval Progressing','"+
        safe(relNum+' '+phaseCode+' L'+curLevel+' approved. Now with '+nextNames+' (L'+nextLevel+')')+"',"+rid+")", {}
      );
      message = phaseCode+' Level '+curLevel+' approved. Sent to Level '+nextLevel+' ('+nextNames+').';
    } else {
      // All levels approved — move to next state
      const afterState = AFTER_APPROVAL[phaseCode];
      newState = afterState;

      await db.executeWithCommit(
        "UPDATE crms_releases SET state='"+safe(afterState)+"',current_approval_level=0,updated_at=SYSDATE WHERE release_id="+rid, {}
      );
      await db.executeWithCommit(
        "INSERT INTO crms_release_history(release_id,action,from_state,to_state,changed_by) "+
        "VALUES("+rid+",'State Change','"+safe(curState)+"','"+safe(afterState)+"',"+uid+")", {}
      );
      await db.executeWithCommit(
        "INSERT INTO crms_audit(action,performed_by,cr_number,details) VALUES("+
        "'State Change',"+uid+",'"+relNum+"','"+phaseCode+" fully approved -> "+safe(afterState)+"')", {}
      );
      await db.executeWithCommit(
        "INSERT INTO crms_notifications(user_id,title,message,release_id) VALUES("+
        reqUserId+",'"+phaseCode+" Fully Approved','"+
        safe(relNum+' '+phaseCode+' fully approved. Moved to '+afterState)+"',"+rid+")", {}
      );

      // Auto-assign Process Owner for the next phase (if mapped)
      try {
        if (release.MODULE_ID) {
          const midStr = num(release.MODULE_ID);
          // RD approved → FSD phase; FSD approved → DEV; etc.
          const phaseToNext = { 'RD':'FSD', 'FSD':'DEV', 'DEV':'TESTING', 'TESTING':'UAT', 'UAT':'DEPLOYMENT' };
          const nextPhaseCode = phaseToNext[phaseCode];
          if (nextPhaseCode) {
            const po = await db.queryOne(
              "SELECT user_id FROM crms_phase_process_owners WHERE module_id="+midStr+
              " AND phase_code='"+nextPhaseCode+"'", {}
            );
            if (po && po.USER_ID) {
              const poUid = num(po.USER_ID);
              await db.executeWithCommit(
                "UPDATE crms_releases SET assigned_to_user_id="+poUid+",updated_at=SYSDATE WHERE release_id="+rid, {}
              );
              await db.executeWithCommit(
                "INSERT INTO crms_notifications(user_id,title,message,release_id) VALUES("+
                poUid+",'CR Auto-Assigned — Process Owner','"+
                safe(relNum+" moved to "+afterState+". You are the Process Owner for the "+nextPhaseCode+" phase.")+
                "',"+rid+")", {}
              );
            }
          }
        }
      } catch(e2) { /* table may not exist yet — skip */ }

      // Auto-assign tasks for the next phase
      const rc = require('./releaseController');
      const nextPhase = rc.stateToPhaseCode(afterState);
      if (nextPhase && release.MODULE_ID) {
        await rc.assignPhaseTasks(rid, release.MODULE_ID, nextPhase, uid);
      }

      message = phaseCode+' fully approved. Moved to '+afterState+'.';
    }

    return res.json({ message, newState, approvedLevel:curLevel, flowType:phaseCode });
  } catch(err) { next(err); }
}

// ── POST /releases/:releaseId/reject ─────────────────────────────────
async function reject(req, res, next) {
  try {
    const rid      = num(req.params.releaseId);
    const uid      = num(req.user.userId);
    const comments = (req.body.comments||'').trim();
    if (!comments) return res.status(422).json({ error:'Rejection reason is required.' });

    const release = await db.queryOne(
      'SELECT release_id,state,release_number,current_approval_level,requested_by '+
      'FROM crms_releases WHERE release_id='+rid+' AND is_deleted=0', {}
    );
    if (!release) return res.status(404).json({ error:'Release not found' });

    const curState  = release.STATE;
    const curLevel  = Number(release.CURRENT_APPROVAL_LEVEL);
    const relNum    = release.RELEASE_NUMBER;
    const reqUserId = num(release.REQUESTED_BY);
    const phaseCode = stateToApprovalPhase(curState);
    if (!phaseCode)
      return res.status(400).json({ error:'Release is not in an approval state.' });

    const mid = await db.queryOne('SELECT module_id FROM crms_releases WHERE release_id='+rid, {})
      .then(function(r){ return r ? num(String(r.MODULE_ID)) : '0'; })
      .catch(function(){ return '0'; });
    await ensureLevelApprovalRecords(rid, mid, phaseCode, curLevel);

    // Return to the phase state
    const returnState = phaseCodeToState(phaseCode);

    const myApproval = await db.queryOne(
      "SELECT approval_id FROM crms_release_approvals "+
      "WHERE release_id="+rid+" AND level_order="+curLevel+
      " AND approver_user_id="+uid+" AND status='Pending' AND phase_code='"+phaseCode+"'", {}
    );
    if (!myApproval)
      return res.status(403).json({ error:'You are not the approver for this level.' });

    // Mark all pending rejected
    await db.executeWithCommit(
      "UPDATE crms_release_approvals SET status='Rejected',comments='"+safe(comments)+"',actioned_at=SYSDATE "+
      "WHERE release_id="+rid+" AND status='Pending' AND phase_code='"+phaseCode+"'", {}
    );
    await db.executeWithCommit(
      "UPDATE crms_releases SET state='"+safe(returnState)+"',current_approval_level=0,updated_at=SYSDATE WHERE release_id="+rid, {}
    );
    await db.executeWithCommit(
      "INSERT INTO crms_release_history(release_id,action,from_state,to_state,changed_by) "+
      "VALUES("+rid+",'State Change','"+safe(curState)+"','"+safe(returnState)+"',"+uid+")", {}
    );
    await db.executeWithCommit(
      "INSERT INTO crms_audit(action,performed_by,cr_number,details) VALUES("+
      "'Rejection',"+uid+",'"+relNum+"','"+phaseCode+" L"+curLevel+" rejected: "+safe(comments.substring(0,80))+"')", {}
    );
    // Post comment
    await db.executeWithCommit(
      "INSERT INTO crms_comments(release_id,comment_text,created_by) VALUES("+
      rid+",'REJECTED ("+phaseCode+" Level "+curLevel+"): "+safe(comments)+"',"+uid+")", {}
    );
    await db.executeWithCommit(
      "INSERT INTO crms_notifications(user_id,title,message,release_id) VALUES("+
      reqUserId+",'"+phaseCode+" Rejected','"+
      safe(relNum+' '+phaseCode+' rejected by '+req.user.fullName+': '+comments.substring(0,80))+"',"+rid+")", {}
    );

    return res.json({ message:'Rejected. Release returned to '+returnState+'.', newState:returnState });
  } catch(err) { next(err); }
}

// ── GET /approvals/pending ────────────────────────────────────────────
async function myPendingApprovals(req, res, next) {
  try {
    const uid  = num(req.user.userId);
    const rows = await db.query(
      'SELECT ra.approval_id,ra.release_id,ra.level_order,ra.phase_code,ra.created_at,'+
      'r.release_number,r.title,r.state,m.module_name,u.full_name AS requested_by '+
      'FROM crms_release_approvals ra '+
      'JOIN crms_releases r ON r.release_id=ra.release_id '+
      'LEFT JOIN crms_modules m ON m.module_id=r.module_id '+
      'JOIN crms_users u ON u.user_id=r.requested_by '+
      'WHERE ra.approver_user_id='+uid+" AND ra.status='Pending' "+
      'AND r.is_deleted=0 AND r.current_approval_level=ra.level_order ORDER BY ra.created_at ASC', {}
    );
    return res.json(rows.map(r => ({
      approvalId:    r.APPROVAL_ID,
      releaseId:     r.RELEASE_ID,
      releaseNumber: r.RELEASE_NUMBER,
      title:         r.TITLE,
      state:         r.STATE,
      levelOrder:    Number(r.LEVEL_ORDER),
      phaseCode:     r.PHASE_CODE,
      moduleName:    r.MODULE_NAME||'—',
      requestedBy:   r.REQUESTED_BY,
      createdAt:     r.CREATED_AT,
    })));
  } catch(err) { next(err); }
}

// ── GET /releases/:releaseId/approval-status ──────────────────────────
async function getApprovalStatus(req, res, next) {
  try {
    const rid  = num(req.params.releaseId);
    const rows = await db.query(
      'SELECT ra.phase_code,ra.level_order,ra.status,ra.comments,ra.actioned_at,u.full_name AS approver_name '+
      'FROM crms_release_approvals ra JOIN crms_users u ON u.user_id=ra.approver_user_id '+
      'WHERE ra.release_id='+rid+' ORDER BY ra.phase_code,ra.level_order', {}
    );
    return res.json(rows.map(r => ({
      phaseCode:    r.PHASE_CODE,
      levelOrder:   Number(r.LEVEL_ORDER),
      status:       r.STATUS,
      approverName: r.APPROVER_NAME,
      comments:     r.COMMENTS,
      actionedAt:   r.ACTIONED_AT,
    })));
  } catch(err) { next(err); }
}

// ── GET /approvals/my-release-status ─────────────────────────────────
async function myReleaseApprovalStatus(req, res, next) {
  try {
    const uid  = num(req.user.userId);
    const rows = await db.query(
      'SELECT ra.release_id,ra.level_order,ra.phase_code,u.full_name AS approver_name '+
      'FROM crms_release_approvals ra '+
      'JOIN crms_users u ON u.user_id=ra.approver_user_id '+
      'JOIN crms_releases r ON r.release_id=ra.release_id '+
      "WHERE r.requested_by="+uid+" AND ra.status='Pending' "+
      'AND r.is_deleted=0 AND r.current_approval_level=ra.level_order ORDER BY ra.release_id', {}
    );
    return res.json(rows.map(r => ({
      releaseId:    r.RELEASE_ID,
      levelOrder:   Number(r.LEVEL_ORDER),
      phaseCode:    r.PHASE_CODE,
      approverName: r.APPROVER_NAME,
    })));
  } catch(err) { next(err); }
}

// ── HELPERS ───────────────────────────────────────────────────────────
function stateToApprovalPhase(state) {
  if (!state) return null;
  var s = state.toLowerCase();
  if (s.startsWith('rd awaiting') || s.startsWith('rd approval'))           return 'RD';
  if (s.startsWith('fsd awaiting') || s.startsWith('fsd approval'))         return 'FSD';
  if (s.startsWith('deployment approval') || s.startsWith('deployment awaiting')) return 'DEPLOYMENT';
  return null;
}

function phaseCodeToState(code) {
  const map = {
    'DRAFT':'Draft', 'RD':'RD Phase', 'FSD':'FSD Phase',
    'DEV':'Development Phase', 'TESTING':'Testing Phase',
    'UAT':'UAT Phase', 'DEPLOYMENT':'Deployment Phase',
  };
  return map[code] || code;
}

// ── GET /approvals/pending — CRs pending current user's approval ──────
async function getPendingApprovals(req, res, next) {
  try {
    const uid = String(parseInt(req.user.userId,10)||0);
    const rows = await db.query(
      'SELECT ra.approval_id,ra.phase_code,ra.level_order,ra.status,'+
      'r.release_id,r.release_number,r.state,r.title,r.priority,r.planned_start_date,'+
      'u_req.full_name AS requested_by,r.created_at '+
      'FROM crms_release_approvals ra '+
      'JOIN crms_releases r ON r.release_id=ra.release_id AND r.is_deleted=0 '+
      'JOIN crms_users u_req ON u_req.user_id=r.requested_by '+
      'WHERE ra.approver_user_id='+uid+" AND ra.status='Pending' "+
      'ORDER BY r.created_at DESC', {}
    );
    return res.json(rows.map(function(r) {
      return {
        approvalId:     r.APPROVAL_ID,
        phaseCode:      r.PHASE_CODE,
        levelOrder:     Number(r.LEVEL_ORDER),
        status:         r.STATUS,
        releaseId:      r.RELEASE_ID,
        releaseNumber:  r.RELEASE_NUMBER,
        releaseState:   r.STATE,
        releaseTitle:   r.TITLE,
        priority:       r.PRIORITY,
        plannedStartDate: r.PLANNED_START_DATE,
        requestedBy:    r.REQUESTED_BY,
        createdAt:      r.CREATED_AT,
      };
    }));
  } catch(err) { next(err); }
}

// ── GET /approvals/is-approver — check if current user is an approver ─
async function isApprover(req, res, next) {
  try {
    const uid = String(parseInt(req.user.userId,10)||0);
    const isMapped = await flowQ.isUserMappedApprover(uid);
    const pending = await db.queryOne(
      'SELECT COUNT(*) AS cnt FROM crms_release_approvals WHERE approver_user_id='+uid+" AND status='Pending'", {}
    );
    return res.json({
      isApprover: isMapped,
      pendingCount: Number(pending.CNT),
    });
  } catch(err) { next(err); }
}


module.exports = {
  triggerApproval,
  approve, reject,
  myPendingApprovals, getApprovalStatus, myReleaseApprovalStatus,
  getPendingApprovals, isApprover,
  ensureLevelApprovalRecords,
  stateToApprovalPhase,
};
