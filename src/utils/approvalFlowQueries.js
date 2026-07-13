'use strict';

const db = require('../config/db');

function safe(s) { return String(s || '').replace(/'/g, "''"); }
function num(n)  { return String(parseInt(n, 10) || 0); }

// Cache the schema state so we don't probe on every request
let _schemaType = null; // 'phase_code' | 'flow_type' | 'none'

async function detectSchema() {
  if (_schemaType) return _schemaType;
  try {
    const col = await db.queryOne(
      "SELECT column_name FROM user_tab_columns WHERE table_name='CRMS_APPROVAL_FLOWS' AND column_name='PHASE_CODE'", {}
    );
    if (col) { _schemaType = 'phase_code'; return _schemaType; }
  } catch(e) {}
  try {
    const col = await db.queryOne(
      "SELECT column_name FROM user_tab_columns WHERE table_name='CRMS_APPROVAL_FLOWS' AND column_name='FLOW_TYPE'", {}
    );
    if (col) { _schemaType = 'flow_type'; return _schemaType; }
  } catch(e) {}
  _schemaType = 'none';
  return _schemaType;
}

// Map phaseCode to the column/value for the current schema
function phaseFilter(schema, phaseCode) {
  if (schema === 'phase_code') {
    return " AND af.phase_code='"+safe(phaseCode)+"'";
  }
  if (schema === 'flow_type') {
    var ft = (phaseCode === 'RD' || phaseCode === 'DRAFT') ? 'RD' : 'FSD';
    return " AND af.flow_type='"+ft+"'";
  }
  return ''; // 'none' — no filter possible, return all
}

function approverUnionSql(mid, phaseCode, schema) {
  const m = num(mid);
  const filter = phaseFilter(schema, phaseCode);
  return (
    "SELECT af.level_order,af.auto_approve,afa.approver_user_id,u.full_name "+
    "FROM crms_approval_flows af "+
    "JOIN crms_approval_flow_approvers afa ON afa.flow_id=af.flow_id "+
    "JOIN crms_users u ON u.user_id=afa.approver_user_id AND u.is_active=1 "+
    "WHERE af.module_id="+m+filter+" "+
    "UNION ALL "+
    "SELECT af.level_order,af.auto_approve,af.approver_user_id,u.full_name "+
    "FROM crms_approval_flows af "+
    "JOIN crms_users u ON u.user_id=af.approver_user_id AND u.is_active=1 "+
    "WHERE af.module_id="+m+filter+" "+
    "AND NOT EXISTS (SELECT 1 FROM crms_approval_flow_approvers afa WHERE afa.flow_id=af.flow_id) "+
    "ORDER BY level_order,full_name"
  );
}

async function queryPhaseApprovers(mid, phaseCode) {
  const schema = await detectSchema();
  try {
    return await db.query(approverUnionSql(mid, phaseCode, schema), {});
  } catch (err) {
    const msg = (err && err.message) || String(err);
    // If crms_approval_flow_approvers table doesn't exist, fall back to simple query
    if (msg.includes('CRMS_APPROVAL_FLOW_APPROVERS') || msg.includes('00942')) {
      const filter = phaseFilter(schema, phaseCode);
      return db.query(
        "SELECT af.level_order,af.auto_approve,af.approver_user_id,u.full_name "+
        "FROM crms_approval_flows af "+
        "JOIN crms_users u ON u.user_id=af.approver_user_id AND u.is_active=1 "+
        "WHERE af.module_id="+num(mid)+filter+" "+
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
  const schema = await detectSchema();
  const filter = phaseFilter(schema, phaseCode).replace('af.','');
  const row = await db.queryOne(
    "SELECT level_order FROM crms_approval_flows "+
    "WHERE module_id="+num(mid)+filter+" AND level_order="+num(levelOrder), {}
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

// Expose detectSchema for use by moduleController's saveLevels
async function getSchemaType() {
  return detectSchema();
}

module.exports = {
  approverUnionSql,
  queryPhaseApprovers,
  queryLevelApprovers,
  hasFlowLevel,
  isUserMappedApprover,
  getSchemaType,
};
