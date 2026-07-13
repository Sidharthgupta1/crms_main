'use strict';

const logger = require('./../config/logger');
const mailer = require('./email/mailer');
const lookup = require('./email/userlookup');
const templates = require('./email/templates');

const APP_BASE = () => process.env.APP_BASE_URL || 'http://localhost:3000';

function timestamp() {
  return new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' });
}

function crLink(releaseId) {
  return `${APP_BASE()}/releases/${releaseId}`;
}

async function sendToRecipients(recipients, subject, htmlTemplate) {
  if (!recipients || !recipients.length) return;
  for (const r of recipients) {
    if (!r.email) continue;
    const html = htmlTemplate(r);
    mailer.sendEmail(r.email, subject, html).catch(() => {});
  }
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

    const phaseLabel = { RD:'RD', FSD:'FSD', DEV:'Development', TESTING:'Testing', UAT:'UAT', DEPLOYMENT:'Deployment', DBA_DEPLOYMENT:'DBA Deployment' }[phaseCode] || phaseCode;

    const recipients = [];

    if (po && po.email) {
      recipients.push({
        email: po.email,
        recipientName: po.fullName,
        message: `The ${phaseLabel} phase has started for CR ${rel.releaseNumber}. ${triggerName ? triggerName + ' has been assigned as the approver.' : ''}`,
      });
    }

    for (const app of approvers) {
      if (!app.email) continue;
      recipients.push({
        email: app.email,
        recipientName: app.fullName,
        message: `A new approval has been assigned to you for CR ${rel.releaseNumber} (${phaseLabel} phase, Level 1). Please review and take action.`,
        level: 1,
        requesterName: reqInfo ? reqInfo.fullName : '',
      });
    }

    if (reqInfo && reqInfo.email) {
      recipients.push({
        email: reqInfo.email,
        recipientName: reqInfo.fullName,
        message: `Your Change Request ${rel.releaseNumber} has entered the ${phaseLabel} phase. ${approvers.length ? 'Current approver: ' + approvers.map(a => a.fullName).join(', ') : 'No approver assigned yet.'}`,
      });
    }

    const common = { crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: phaseLabel, timestamp: ts, link };
    for (const r of recipients) {
      let html;
      if (r.level) {
        html = templates.approvalRequiredTemplate({ ...common, recipientName: r.recipientName, message: r.message, level: r.level, requesterName: r.requesterName || '' });
      } else {
        html = templates.phaseStartedTemplate({ ...common, recipientName: r.recipientName, message: r.message });
      }
      mailer.sendEmail(r.email, r.level ? `Action Required - ${phaseLabel} Approval` : `${phaseLabel} Phase Started`, html).catch(() => {});
    }
  } catch (err) {
    logger.error('[EmailService] sendPhaseStarted failed', { releaseId, phaseCode, error: err.message });
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
    const phaseLabel = { RD:'RD', FSD:'FSD', DEV:'Development', TESTING:'Testing', UAT:'UAT', DEPLOYMENT:'Deployment', DBA_DEPLOYMENT:'DBA Deployment' }[phaseCode] || phaseCode;
    const common = { crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: phaseLabel, level, approvedBy: approvedByName, timestamp: ts, link };

    if (po && po.email) {
      const html = templates.approvalCompletedTemplate({
        ...common, recipientName: po.fullName,
        message: `${approvedByName} approved the ${phaseLabel} Level ${level} task for CR ${rel.releaseNumber}.`,
      });
      mailer.sendEmail(po.email, `${phaseLabel} Level ${level} Approved`, html).catch(() => {});
    }

    if (reqInfo && reqInfo.email) {
      const html = templates.approvalCompletedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `${approvedByName} approved your ${phaseLabel} Level ${level} request for CR ${rel.releaseNumber}.`,
      });
      mailer.sendEmail(reqInfo.email, `${phaseLabel} Level ${level} Approved`, html).catch(() => {});
    }

    if (isFinal) {
      if (po && po.email) {
        const html = templates.phaseCompletedTemplate({
          ...common, recipientName: po.fullName, level: undefined,
          message: `The ${phaseLabel} phase has been fully approved and completed for CR ${rel.releaseNumber}.`,
        });
        mailer.sendEmail(po.email, `${phaseLabel} Phase Completed`, html).catch(() => {});
      }
      if (reqInfo && reqInfo.email) {
        const html = templates.phaseCompletedTemplate({
          ...common, recipientName: reqInfo.fullName, level: undefined,
          message: `The ${phaseLabel} phase has been completed for your CR ${rel.releaseNumber}.`,
        });
        mailer.sendEmail(reqInfo.email, `${phaseLabel} Phase Completed`, html).catch(() => {});
      }
    }

    if (nextLevelApproverIds && nextLevelApproverIds.length) {
      const nextApprovers = await lookup.getUsersEmails(nextLevelApproverIds);
      for (const na of nextApprovers) {
        if (!na.email) continue;
        const html = templates.approvalRequiredTemplate({
          ...common, recipientName: na.fullName, level: level + 1, requesterName: reqInfo ? reqInfo.fullName : '',
          message: `CR ${rel.releaseNumber} requires your ${phaseLabel} Level ${level + 1} approval. Previous level approved by ${approvedByName}.`,
        });
        mailer.sendEmail(na.email, `Action Required - ${phaseLabel} Level ${level + 1} Approval`, html).catch(() => {});
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
    const phaseLabel = { RD:'RD', FSD:'FSD', DEV:'Development', TESTING:'Testing', UAT:'UAT', DEPLOYMENT:'Deployment', DBA_DEPLOYMENT:'DBA Deployment' }[phaseCode] || phaseCode;
    const common = { crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: phaseLabel, rejectedBy: rejectedByName, remarks: remarks || 'No remarks provided', timestamp: ts, link };

    if (reqInfo && reqInfo.email) {
      const html = templates.approvalRejectedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `Your ${phaseLabel} Level ${level} request for CR ${rel.releaseNumber} has been rejected by ${rejectedByName}.`,
      });
      mailer.sendEmail(reqInfo.email, `${phaseLabel} Approval Rejected`, html).catch(() => {});
    }

    if (po && po.email) {
      const html = templates.approvalRejectedTemplate({
        ...common, recipientName: po.fullName,
        message: `${rejectedByName} rejected the ${phaseLabel} Level ${level} approval for CR ${rel.releaseNumber}.`,
      });
      mailer.sendEmail(po.email, `${phaseLabel} Approval Rejected`, html).catch(() => {});
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
    const phaseLabel = { RD:'RD', FSD:'FSD', DEV:'Development', TESTING:'Testing', UAT:'UAT', DEPLOYMENT:'Deployment', DBA_DEPLOYMENT:'DBA Deployment' }[phaseCode] || phaseCode;

    const taskInfo = await lookup.getReleaseInfo(releaseId); // reuse
    if (assignedUser && assignedUser.email) {
      const html = templates.subtaskAssignedTemplate({
        crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: phaseLabel,
        taskNumber: `TASK-${taskId}`, taskDescription: '', assignedBy: creatorUser ? creatorUser.fullName : 'System',
        recipientName: assignedUser.fullName, timestamp: ts, link,
        message: `You have been assigned a new sub-task on CR ${rel.releaseNumber} (${phaseLabel} phase).`,
      });
      mailer.sendEmail(assignedUser.email, 'New Sub-Task Assigned', html).catch(() => {});
    }

    if (creatorUser && creatorUser.email) {
      const html = templates.subtaskAssignedTemplate({
        crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: phaseLabel,
        taskNumber: `TASK-${taskId}`, taskDescription: '', assignedBy: creatorUser.fullName,
        recipientName: creatorUser.fullName, timestamp: ts, link,
        message: `Your sub-task on CR ${rel.releaseNumber} (${phaseLabel} phase) has been assigned to ${assignedUser ? assignedUser.fullName : 'a user'}.`,
      });
      mailer.sendEmail(creatorUser.email, 'Sub-Task Assigned Successfully', html).catch(() => {});
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
    const phaseLabel = { RD:'RD', FSD:'FSD', DEV:'Development', TESTING:'Testing', UAT:'UAT', DEPLOYMENT:'Deployment', DBA_DEPLOYMENT:'DBA Deployment' }[phaseCode] || phaseCode;

    const taskRow = await lookup.getReleaseInfo(releaseId);
    const assigneeEmails = [];

    const creatorEmails = [];

    const common = { crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: phaseLabel,
      taskNumber: `TASK-${taskId}`, completedBy: completedBy || 'Unknown', timestamp: ts, link };

    const htmlCreator = templates.subtaskCompletedTemplate({
      ...common,
      recipientName: 'Task Creator',
      message: `${completedBy} has completed the assigned sub-task on CR ${rel.releaseNumber} (${phaseLabel} phase).`,
    });
    const htmlAssignee = templates.subtaskCompletedTemplate({
      ...common,
      recipientName: 'Assignee',
      message: `You have successfully completed the sub-task on CR ${rel.releaseNumber} (${phaseLabel} phase).`,
    });

    try {
      const taskCreator = await lookup.getUsersEmails([completedByUserId]);
      if (taskCreator[0] && taskCreator[0].email) {
        mailer.sendEmail(taskCreator[0].email, 'Sub-Task Completed', htmlCreator).catch(() => {});
      }
    } catch (e) {}
  } catch (err) {
    logger.error('[EmailService] sendSubtaskCompleted failed', { releaseId, taskId, error: err.message });
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
    const phaseLabel = { RD:'RD', FSD:'FSD', DEV:'Development', TESTING:'Testing', UAT:'UAT', DEPLOYMENT:'Deployment', DBA_DEPLOYMENT:'DBA Deployment' }[phaseCode] || phaseCode;
    const common = { crNumber: rel.releaseNumber, moduleName: rel.moduleName, phase: phaseLabel, timestamp: ts, link };

    if (po && po.email) {
      const html = templates.phaseCompletedTemplate({
        ...common, recipientName: po.fullName,
        message: `The ${phaseLabel} phase has been completed for CR ${rel.releaseNumber}.`,
      });
      mailer.sendEmail(po.email, `${phaseLabel} Phase Completed`, html).catch(() => {});
    }

    if (reqInfo && reqInfo.email) {
      const html = templates.phaseCompletedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `The ${phaseLabel} phase has been completed for your CR ${rel.releaseNumber}.`,
      });
      mailer.sendEmail(reqInfo.email, `${phaseLabel} Phase Completed`, html).catch(() => {});
    }
  } catch (err) {
    logger.error('[EmailService] sendPhaseCompleted failed', { releaseId, phaseCode, error: err.message });
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
      const html = templates.deploymentCompletedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `Deployment has been completed for your CR ${rel.releaseNumber}.`,
      });
      mailer.sendEmail(reqInfo.email, 'Deployment Completed', html).catch(() => {});
    }

    if (po && po.email) {
      const html = templates.deploymentCompletedTemplate({
        ...common, recipientName: po.fullName,
        message: `Deployment has been completed for CR ${rel.releaseNumber}.`,
      });
      mailer.sendEmail(po.email, 'Deployment Completed', html).catch(() => {});
    }
  } catch (err) {
    logger.error('[EmailService] sendDeploymentCompleted failed', { releaseId, error: err.message });
  }
}

module.exports = {
  sendPhaseStarted, sendPhaseCompleted, sendApprovalCompleted, sendApprovalRejected,
  sendSubtaskAssigned, sendSubtaskCompleted, sendDeploymentCompleted,
};