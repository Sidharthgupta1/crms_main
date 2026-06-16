'use strict';

const db = require('../config/db');

function safe(s) { return String(s || '').replace(/'/g, "''"); }
function num(n)  { return String(parseInt(n, 10) || 0); }

function approverUnionSql(mid, phaseCode) {
  const m = num(mid);
  const p = safe(phaseCode);
  return (
    "SELECT af.level_order,af.auto_approve,afa.approver_user_id,u.full_name "+
    "FROM crms_approval_flows af "+
    "JOIN crms_approval_flow_approvers afa ON afa.flow_id=af.flow_id "+
    "JOIN crms_users u ON u.user_id=afa.approver_user_id AND u.is_active=1 "+
    "WHERE af.module_id="+m+" AND af.phase_code='"+p+"' "+
    "UNION ALL "+
    "SELECT af.level_order,af.auto_approve,af.approver_user_id,u.full_name "+
    "FROM crms_approval_flows af "+
    "JOIN crms_users u ON u.user_id=af.approver_user_id AND u.is_active=1 "+
    "WHERE af.module_id="+m+" AND af.phase_code='"+p+"' "+
    "AND NOT EXISTS (SELECT 1 FROM crms_approval_flow_approvers afa WHERE afa.flow_id=af.flow_id) "+
    "ORDER BY level_order,full_name"
  );
}

async function queryPhaseApprovers(mid, phaseCode) {
  try {
    return await db.query(approverUnionSql(mid, phaseCode), {});
  } catch (err) {
    const msg = (err && err.message) || String(err);
    if (msg.includes('CRMS_APPROVAL_FLOW_APPROVERS') || msg.includes('00942')) {
      return db.query(
        "SELECT af.level_order,af.auto_approve,af.approver_user_id,u.full_name "+
        "FROM crms_approval_flows af "+
        "JOIN crms_users u ON u.user_id=af.approver_user_id AND u.is_active=1 "+
        "WHERE af.module_id="+num(mid)+" AND af.phase_code='"+safe(phaseCode)+"' "+
        "ORDER BY af.level_order,u.full_name", {}
      ).catch(function() { return []; });
    }
    return [];
  }
}

async function queryLevelApprovers(mid, phaseCode, levelOrder) {
  const lvl = Number(levelOrder);
  const rows = await queryPhaseApprovers(mid, phaseCode);
  return rows.filter(function(r) { return Number(r.LEVEL_ORDER) === lvl; });
}

async function hasFlowLevel(mid, phaseCode, levelOrder) {
  const row = await db.queryOne(
    "SELECT level_order FROM crms_approval_flows "+
    "WHERE module_id="+num(mid)+" AND phase_code='"+safe(phaseCode)+"' AND level_order="+num(levelOrder), {}
  ).catch(function() { return null; });
  return !!row;
}

async function isUserMappedApprover(uid) {
  const u = num(uid);
  try {
    const row = await db.queryOne(
      "SELECT COUNT(*) AS cnt FROM ("+
      "SELECT afa.approver_user_id FROM crms_approval_flow_approvers afa WHERE afa.approver_user_id="+u+
      " UNION "+
      "SELECT af.approver_user_id FROM crms_approval_flows af "+
      "WHERE af.approver_user_id="+u+
      " AND NOT EXISTS (SELECT 1 FROM crms_approval_flow_approvers afa WHERE afa.flow_id=af.flow_id)"+
      ")", {}
    );
    return Number(row.CNT) > 0;
  } catch (err) {
    const msg = (err && err.message) || String(err);
    if (msg.includes('CRMS_APPROVAL_FLOW_APPROVERS') || msg.includes('00942')) {
      const row = await db.queryOne(
        'SELECT COUNT(*) AS cnt FROM crms_approval_flows WHERE approver_user_id='+u, {}
      ).catch(function() { return { CNT: 0 }; });
      return Number(row.CNT) > 0;
    }
    return false;
  }
}

module.exports = {
  approverUnionSql,
  queryPhaseApprovers,
  queryLevelApprovers,
  hasFlowLevel,
  isUserMappedApprover,
};
