'use strict';

const db = require('./../config/db');
const logger = require('./../config/logger');
const mailer = require('./email/mailer');
const lookup = require('./email/userLookup');
const templates = require('./email/templates');

const APP_BASE = () => process.env.APP_BASE_URL || 'http://localhost:3000';

function timestamp() {
  return new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' });
}

function crLink(releaseId) {
  return `${APP_BASE()}/releases/${releaseId}`;
}

function num(n) { return String(parseInt(n, 10) || 0); }
function safe(s) { return String(s || '').replace(/'/g, "''"); }

async function insertNotification(userId, title, message, releaseId) {
  if (!userId) return;
  try {
    await db.executeWithCommit(
      "INSERT INTO crms_notifications(user_id,title,message,release_id) VALUES(" +
      num(userId) + ",'" + safe(title) + "','" + safe(message) + "'," + num(releaseId) + ")", {}
    );
  } catch (err) {
    logger.warn('[EmailService] insertNotification failed', { userId, releaseId, error: err.message });
  }
}

async function sendMailSafe(email, subject, html) {
  if (!email) return;
  try {
    const result = await mailer.sendEmail(email, subject, html);
    if (result.success) {
      logger.info('[EmailService] Email sent', { to: email, subject });
    } else {
      logger.error('[EmailService] Email send returned failure', { to: email, subject, error: result.error });
    }
    return result;
  } catch (err) {
    logger.error('[EmailService] Email send threw', { to: email, subject, error: err.message });
    return { success: false, error: err.message };
  }
}

const PHASE_LABELS = { RD:'RD', FSD:'FSD', DEV:'Development', TESTING:'Testing', UAT:'UAT', DEPLOYMENT:'Deployment', DBA_DEPLOYMENT:'DBA Deployment', OBSERVATION:'Observation' };
function phaseLabel(phaseCode) {
  return PHASE_LABELS[phaseCode] || phaseCode;
}

async function sendPhaseStarted(releaseId, phaseCode, triggeredByUserId) {
  try {
    const rel = await lookup.getReleaseInfo(releaseId);
    if (!rel) return;
    const reqInfo = await lookup.getRequesterInfo(releaseId);
    const po = await lookup.getProcessOwner(rel.moduleId, phaseCode);
    const approvers = await lookup.getLevel1Approvers(rel.moduleId, phaseCode);
    const triggerName = await lookup.getUserName(triggeredByUserId);
    const ts = timestamp();
    const link = crLink(releaseId);
    const label = phaseLabel(phaseCode);

    const recipients = [];

    if (po && po.email) {
      recipients.push({
        email: po.email,
        recipientName: po.fullName,
        message: `The ${label} phase has started for CR ${rel.releaseNumber}. ${triggerName ? triggerName + ' has been assigned as the approver.' : ''}`,
      });
    }

    for (const app of approvers) {
      if (!app.email) continue;
      recipients.push({
        email: app.email,
        recipientName: app.fullName,
        message: `A new approval has been assigned to you for CR ${rel.releaseNumber} (${label} phase, Level 1). Please review and take action.`,
        level: 1,
        requesterName: reqInfo ? reqInfo.fullName : '',
      });
    }

    if (reqInfo && reqInfo.email) {
      recipients.push({
        email: reqInfo.email,
        recipientName: reqInfo.fullName,
        message: `Your Change Request ${rel.releaseNumber} has entered the ${label} phase. ${approvers.length ? 'Current approver: ' + approvers.map(a => a.fullName).join(', ') : 'No approver assigned yet.'}`,
      });
    }

    const common = { crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: label, timestamp: ts, link };
    for (const r of recipients) {
      let html;
      if (r.level) {
        html = templates.approvalRequiredTemplate({ ...common, recipientName: r.recipientName, message: r.message, level: r.level, requesterName: r.requesterName || '' });
      } else {
        html = templates.phaseStartedTemplate({ ...common, recipientName: r.recipientName, message: r.message });
      }
      await sendMailSafe(r.email, r.level ? `Action Required - ${label} Approval` : `${label} Phase Started`, html);
    }
  } catch (err) {
    logger.error('[EmailService] sendPhaseStarted failed', { releaseId, phaseCode, error: err.message });
  }
}

async function sendPhaseCompleted(releaseId, phaseCode) {
  try {
    const rel = await lookup.getReleaseInfo(releaseId);
    if (!rel) return;
    const reqInfo = await lookup.getRequesterInfo(releaseId);
    const po = await lookup.getProcessOwner(rel.moduleId, phaseCode);
    const ts = timestamp();
    const link = crLink(releaseId);
    const label = phaseLabel(phaseCode);
    const common = { crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: label, timestamp: ts, link };

    if (po && po.email) {
      await insertNotification(po.userId, `${label} Phase Completed`, `The ${label} phase has been fully approved and completed for CR ${rel.releaseNumber}.`, releaseId);
      const html = templates.phaseCompletedTemplate({
        ...common, recipientName: po.fullName,
        message: `The ${label} phase has been fully approved and completed for CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(po.email, `${label} Phase Completed`, html);
    }

    if (reqInfo && reqInfo.email) {
      await insertNotification(reqInfo.userId, `${label} Phase Completed`, `The ${label} phase has been completed for your CR ${rel.releaseNumber}.`, releaseId);
      const html = templates.phaseCompletedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `The ${label} phase has been completed for your CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(reqInfo.email, `${label} Phase Completed`, html);
    }
  } catch (err) {
    logger.error('[EmailService] sendPhaseCompleted failed', { releaseId, phaseCode, error: err.message });
  }
}

async function sendApprovalCompleted(releaseId, phaseCode, level, approvedByUserId, isFinal, nextLevelApproverIds) {
  try {
    const rel = await lookup.getReleaseInfo(releaseId);
    if (!rel) return;
    const reqInfo = await lookup.getRequesterInfo(releaseId);
    const po = await lookup.getProcessOwner(rel.moduleId, phaseCode);
    const approvedByName = await lookup.getUserName(approvedByUserId);
    const ts = timestamp();
    const link = crLink(releaseId);
    const label = phaseLabel(phaseCode);
    const common = { crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: label, level, approvedBy: approvedByName, timestamp: ts, link };

    if (po && po.email) {
      const html = templates.approvalCompletedTemplate({
        ...common, recipientName: po.fullName,
        message: `${approvedByName} approved the ${label} Level ${level} task for CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(po.email, `${label} Level ${level} Approved`, html);
    }

    if (reqInfo && reqInfo.email) {
      await insertNotification(reqInfo.userId, `${label} Level ${level} Approved`, `${approvedByName} approved your ${label} Level ${level} request for CR ${rel.releaseNumber}.`, releaseId);
      const html = templates.approvalCompletedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `${approvedByName} approved your ${label} Level ${level} request for CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(reqInfo.email, `${label} Level ${level} Approved`, html);
    }

    if (isFinal) {
      if (po && po.email) {
        const html = templates.phaseCompletedTemplate({
          ...common, recipientName: po.fullName, level: undefined,
          message: `The ${label} phase has been fully approved and completed for CR ${rel.releaseNumber}.`,
        });
        await sendMailSafe(po.email, `${label} Phase Completed`, html);
      }
      if (reqInfo && reqInfo.email) {
        const html = templates.phaseCompletedTemplate({
          ...common, recipientName: reqInfo.fullName, level: undefined,
          message: `The ${label} phase has been completed for your CR ${rel.releaseNumber}.`,
        });
        await sendMailSafe(reqInfo.email, `${label} Phase Completed`, html);
      }
    }

    if (nextLevelApproverIds && nextLevelApproverIds.length) {
      const nextApprovers = await lookup.getUsersEmails(nextLevelApproverIds);
      for (const na of nextApprovers) {
        if (!na.email) continue;
        const html = templates.approvalRequiredTemplate({
          ...common, recipientName: na.fullName, level: level + 1, requesterName: reqInfo ? reqInfo.fullName : '',
          message: `CR ${rel.releaseNumber} requires your ${label} Level ${level + 1} approval. Previous level approved by ${approvedByName}.`,
        });
        await sendMailSafe(na.email, `Action Required - ${label} Level ${level + 1} Approval`, html);
      }
    }
  } catch (err) {
    logger.error('[EmailService] sendApprovalCompleted failed', { releaseId, phaseCode, error: err.message });
  }
}

async function sendApprovalRejected(releaseId, phaseCode, level, rejectedByUserId, remarks) {
  try {
    const rel = await lookup.getReleaseInfo(releaseId);
    if (!rel) return;
    const reqInfo = await lookup.getRequesterInfo(releaseId);
    const po = await lookup.getProcessOwner(rel.moduleId, phaseCode);
    const rejectedByName = await lookup.getUserName(rejectedByUserId);
    const ts = timestamp();
    const link = crLink(releaseId);
    const label = phaseLabel(phaseCode);
    const common = { crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: label, rejectedBy: rejectedByName, remarks: remarks || 'No remarks provided', timestamp: ts, link };

    if (reqInfo && reqInfo.email) {
      await insertNotification(reqInfo.userId, `${label} Approval Rejected`, `Your ${label} Level ${level} request for CR ${rel.releaseNumber} has been rejected by ${rejectedByName}.`, releaseId);
      const html = templates.approvalRejectedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `Your ${label} Level ${level} request for CR ${rel.releaseNumber} has been rejected by ${rejectedByName}.`,
      });
      await sendMailSafe(reqInfo.email, `${label} Approval Rejected`, html);
    }

    if (po && po.email) {
      const html = templates.approvalRejectedTemplate({
        ...common, recipientName: po.fullName,
        message: `${rejectedByName} rejected the ${label} Level ${level} approval for CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(po.email, `${label} Approval Rejected`, html);
    }
  } catch (err) {
    logger.error('[EmailService] sendApprovalRejected failed', { releaseId, phaseCode, error: err.message });
  }
}

async function sendSubtaskAssigned(releaseId, taskId, phaseCode, assignedToUserId, createdByUserId) {
  try {
    const rel = await lookup.getReleaseInfo(releaseId);
    if (!rel) return;
    const [assignee, creator] = await Promise.all([
      lookup.getUsersEmails([assignedToUserId]),
      lookup.getUsersEmails([createdByUserId]),
    ]);
    const assignedUser = assignee[0];
    const creatorUser = creator[0];
    if (!assignedUser && !creatorUser) return;
    const ts = timestamp();
    const link = crLink(releaseId);
    const label = phaseLabel(phaseCode);

    if (assignedUser && assignedUser.email) {
      await insertNotification(assignedUser.userId, 'Sub-Task Assigned', `You have been assigned a new sub-task on CR ${rel.releaseNumber} (${label} phase).`, releaseId);
      const html = templates.subtaskAssignedTemplate({
        crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: label,
        taskNumber: `TASK-${taskId}`, taskDescription: '', assignedBy: creatorUser ? creatorUser.fullName : 'System',
        recipientName: assignedUser.fullName, timestamp: ts, link,
        message: `You have been assigned a new sub-task on CR ${rel.releaseNumber} (${label} phase).`,
      });
      await sendMailSafe(assignedUser.email, 'New Sub-Task Assigned', html);
    }

    if (creatorUser && creatorUser.email) {
      const html = templates.subtaskAssignedTemplate({
        crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: label,
        taskNumber: `TASK-${taskId}`, taskDescription: '', assignedBy: creatorUser.fullName,
        recipientName: creatorUser.fullName, timestamp: ts, link,
        message: `Your sub-task on CR ${rel.releaseNumber} (${label} phase) has been assigned to ${assignedUser ? assignedUser.fullName : 'a user'}.`,
      });
      await sendMailSafe(creatorUser.email, 'Sub-Task Assigned Successfully', html);
    }
  } catch (err) {
    logger.error('[EmailService] sendSubtaskAssigned failed', { releaseId, taskId, error: err.message });
  }
}

async function sendSubtaskCompleted(releaseId, taskId, phaseCode, completedByUserId) {
  try {
    const rel = await lookup.getReleaseInfo(releaseId);
    if (!rel) return;
    const completedBy = await lookup.getUserName(completedByUserId);
    const ts = timestamp();
    const link = crLink(releaseId);
    const label = phaseLabel(phaseCode);

    const common = { crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: label,
      taskNumber: `TASK-${taskId}`, completedBy: completedBy || 'Unknown', timestamp: ts, link };

    const reqInfo = await lookup.getRequesterInfo(releaseId);

    if (reqInfo && reqInfo.email) {
      await insertNotification(reqInfo.userId, 'Sub-Task Completed', `${completedBy} has completed the assigned sub-task on CR ${rel.releaseNumber} (${label} phase).`, releaseId);
      const html = templates.subtaskCompletedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `${completedBy} has completed the assigned sub-task on CR ${rel.releaseNumber} (${label} phase).`,
      });
      await sendMailSafe(reqInfo.email, 'Sub-Task Completed', html);
    }
  } catch (err) {
    logger.error('[EmailService] sendSubtaskCompleted failed', { releaseId, taskId, error: err.message });
  }
}

async function sendDeploymentCompleted(releaseId) {
  try {
    const rel = await lookup.getReleaseInfo(releaseId);
    if (!rel) return;
    const reqInfo = await lookup.getRequesterInfo(releaseId);
    const po = await lookup.getProcessOwner(rel.moduleId, 'DEPLOYMENT');
    const ts = timestamp();
    const link = crLink(releaseId);
    const common = { crNumber: rel.releaseNumber, moduleName: rel.moduleName, timestamp: ts, link };

    if (reqInfo && reqInfo.email) {
      await insertNotification(reqInfo.userId, 'Deployment Completed', `Deployment has been completed for your CR ${rel.releaseNumber}.`, releaseId);
      const html = templates.deploymentCompletedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `Deployment has been completed for your CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(reqInfo.email, 'Deployment Completed', html);
    }

    if (po && po.email) {
      const html = templates.deploymentCompletedTemplate({
        ...common, recipientName: po.fullName,
        message: `Deployment has been completed for CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(po.email, 'Deployment Completed', html);
    }
  } catch (err) {
    logger.error('[EmailService] sendDeploymentCompleted failed', { releaseId, error: err.message });
  }
}

module.exports = {
  insertNotification,
  sendPhaseStarted, sendPhaseCompleted, sendApprovalCompleted, sendApprovalRejected,
  sendSubtaskAssigned, sendSubtaskCompleted, sendDeploymentCompleted,
};