'use strict';

const db = require('../../config/db');
const logger = require('../../config/logger');

function num(n) { return String(parseInt(n, 10) || 0); }
function safe(s) { return String(s || '').replace(/'/g, "''"); }

async function getUserEmail(userId) {
  if (!userId) return null;
  try {
    const row = await db.queryOne(
      "SELECT email_address FROM crms_users WHERE user_id=" + num(userId) + " AND is_active=1", {}
    );
    return row ? row.EMAIL_ADDRESS : null;
  } catch (err) {
    logger.warn('[EmailLookup] getUserEmail failed', { userId, error: err.message });
    return null;
  }
}

async function getUserName(userId) {
  if (!userId) return null;
  try {
    const row = await db.queryOne(
      "SELECT full_name FROM crms_users WHERE user_id=" + num(userId), {}
    );
    return row ? row.FULL_NAME : null;
  } catch (err) {
    logger.warn('[EmailLookup] getUserName failed', { userId, error: err.message });
    return null;
  }
}

async function getUsersEmails(userIds) {
  if (!userIds || !userIds.length) return [];
  const ids = userIds.map(id => num(id)).filter(id => id !== '0').join(',');
  if (!ids) return [];
  try {
    const rows = await db.query(
      "SELECT user_id, email_address, full_name FROM crms_users WHERE user_id IN (" + ids + ") AND is_active=1", {}
    );
    return rows.map(r => ({
      userId: num(r.USER_ID),
      email: r.EMAIL_ADDRESS,
      fullName: r.FULL_NAME,
    }));
  } catch (err) {
    logger.warn('[EmailLookup] getUsersEmails failed', { userIds, error: err.message });
    return [];
  }
}

async function getProcessOwner(moduleId, phaseCode) {
  if (!moduleId || !phaseCode) return null;
  try {
    const row = await db.queryOne(
      "SELECT po.user_id, u.email_address, u.full_name FROM crms_phase_process_owners po " +
      "JOIN crms_users u ON u.user_id = po.user_id " +
      "WHERE po.module_id=" + num(moduleId) + " AND po.phase_code='" + safe(phaseCode) + "'", {}
    );
    return row ? { userId: num(row.USER_ID), email: row.EMAIL_ADDRESS, fullName: row.FULL_NAME } : null;
  } catch (err) {
    logger.warn('[EmailLookup] getProcessOwner failed', { moduleId, phaseCode, error: err.message });
    return null;
  }
}

async function getLevel1Approvers(moduleId, phaseCode) {
  if (!moduleId || !phaseCode) return [];
  try {
    const flowRows = await db.query(
      "SELECT afa.approver_user_id, u.email_address, u.full_name FROM crms_approval_flows af " +
      "JOIN crms_approval_flow_approvers afa ON afa.flow_id = af.flow_id " +
      "JOIN crms_users u ON u.user_id = afa.approver_user_id AND u.is_active=1 " +
      "WHERE af.module_id=" + num(moduleId) + " AND af.phase_code='" + safe(phaseCode) + "' AND af.level_order=1 " +
      "UNION ALL " +
      "SELECT af.approver_user_id, u.email_address, u.full_name FROM crms_approval_flows af " +
      "JOIN crms_users u ON u.user_id = af.approver_user_id AND u.is_active=1 " +
      "WHERE af.module_id=" + num(moduleId) + " AND af.phase_code='" + safe(phaseCode) + "' AND af.level_order=1 " +
      "AND NOT EXISTS (SELECT 1 FROM crms_approval_flow_approvers afa WHERE afa.flow_id = af.flow_id)", {}
    );
    return flowRows.map(r => ({
      userId: num(r.APPROVER_USER_ID),
      email: r.EMAIL_ADDRESS,
      fullName: r.FULL_NAME,
    }));
  } catch (err) {
    logger.warn('[EmailLookup] getLevel1Approvers failed', { moduleId, phaseCode, error: err.message });
    return [];
  }
}

async function getRequesterInfo(releaseId) {
  if (!releaseId) return null;
  try {
    const row = await db.queryOne(
      "SELECT r.requested_by, u.email_address, u.full_name FROM crms_releases r " +
      "JOIN crms_users u ON u.user_id = r.requested_by " +
      "WHERE r.release_id=" + num(releaseId), {}
    );
    return row ? { userId: num(row.REQUESTED_BY), email: row.EMAIL_ADDRESS, fullName: row.FULL_NAME } : null;
  } catch (err) {
    logger.warn('[EmailLookup] getRequesterInfo failed', { releaseId, error: err.message });
    return null;
  }
}

async function getReleaseInfo(releaseId) {
  if (!releaseId) return null;
  try {
    const row = await db.queryOne(
      "SELECT r.release_id, r.release_number, r.state, r.title, m.module_name, " +
      "r.module_id FROM crms_releases r " +
      "LEFT JOIN crms_modules m ON m.module_id = r.module_id " +
      "WHERE r.release_id=" + num(releaseId), {}
    );
    if (!row) return null;
    return {
      releaseId: num(row.RELEASE_ID),
      releaseNumber: row.RELEASE_NUMBER,
      state: row.STATE,
      title: row.TITLE,
      moduleName: row.MODULE_NAME || '',
      moduleId: row.MODULE_ID,
    };
  } catch (err) {
    logger.warn('[EmailLookup] getReleaseInfo failed', { releaseId, error: err.message });
    return null;
  }
}

module.exports = {
  getUserEmail, getUserName, getUsersEmails,
  getProcessOwner, getLevel1Approvers, getRequesterInfo, getReleaseInfo,
};