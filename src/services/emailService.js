'use strict';

const db = require('./../config/db');
const logger = require('./../config/logger');
const mailer = require('./email/mailer');
const lookup = require('./email/userLookup');
const templates = require('./email/templates');
const emailActionCtrl = require('../controllers/emailActionController');

const APP_BASE = () => process.env.APP_BASE_URL || 'http://localhost:3000';
const API_PREFIX = process.env.API_PREFIX || '/api/v1';

// One-click Approve/Reject links for the approval-required email — each is a
// signed, single-purpose, expiring token (see emailActionController.js), not
// a plain/guessable URL. Opening the link performs the action immediately,
// per explicit business decision (no confirmation page).
function approveLink(releaseId, approverUserId) {
  const token = emailActionCtrl.makeActionToken({ releaseId: Number(releaseId), userId: Number(approverUserId), action: 'approve' });
  return `${APP_BASE()}${API_PREFIX}/email-actions/${token}`;
}
function rejectLink(releaseId, approverUserId) {
  const token = emailActionCtrl.makeActionToken({ releaseId: Number(releaseId), userId: Number(approverUserId), action: 'reject' });
  return `${APP_BASE()}${API_PREFIX}/email-actions/${token}`;
}

function timestamp() {
  return new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' });
}

// Deep link: the SPA is served at APP_BASE's root; ?openRelease=<id> is read
// on load (or after login, if not yet authenticated) and auto-opens that CR's
// detail modal — see the "openRelease deep link" block in cr-management-system.html.
function crLink(releaseId) {
  return `${APP_BASE()}/?openRelease=${releaseId}`;
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

// cc is a ';'-separated list of addresses to carbon-copy (the recipient's
// own CC_EMAIL_ADDRESS, the CR Owner's address from FSD onward, or both —
// see mergeCc below).
async function sendMailSafe(email, cc, subject, html) {
  if (!email) return;
  try {
    const result = await mailer.sendEmail(email, subject, html, cc);
    if (result.success) {
      logger.info('[EmailService] Email sent', { to: email, cc, subject });
    } else {
      logger.error('[EmailService] Email send returned failure', { to: email, cc, subject, error: result.error });
    }
    return result;
  } catch (err) {
    logger.error('[EmailService] Email send threw', { to: email, cc, subject, error: err.message });
    return { success: false, error: err.message };
  }
}

const PHASE_LABELS = { RD:'RD', FSD:'FSD', DEV:'Development', TESTING:'Testing', UAT:'UAT', DEPLOYMENT:'Deployment', DBA_DEPLOYMENT:'DBA Deployment', OBSERVATION:'Observation' };
function phaseLabel(phaseCode) {
  return PHASE_LABELS[phaseCode] || phaseCode;
}

// CR Owner is set during FSD (the Process Owner assigns it) and, per
// business rule, gets CC'd on every CRMS notification for that CR from FSD
// onward — never during RD, since the CR Owner isn't assigned yet.
const CR_OWNER_CC_PHASES = new Set(['FSD', 'DEV', 'TESTING', 'UAT', 'DEPLOYMENT', 'DBA_DEPLOYMENT', 'OBSERVATION']);
// Legacy crms_tasks phase vocabulary (BRD/FSD/Dev/Testing/UAT) — only the
// RD-equivalent ('BRD') is excluded.
const LEGACY_CR_OWNER_CC_PHASES = new Set(['FSD', 'Dev', 'Testing', 'UAT']);

function isFsdOrLater(phaseCode) { return !!phaseCode && CR_OWNER_CC_PHASES.has(phaseCode); }
function isLegacyFsdOrLater(phase) { return !!phase && LEGACY_CR_OWNER_CC_PHASES.has(phase); }

// Maps a CR's free-text state (e.g. "FSD Awaiting Approval L2") to a phase
// code — used only by sendCrAssigned, which doesn't already have a
// phaseCode handy. Unknown/terminal states (On Hold, Closed, Cancelled,
// Draft) return null, so no CR Owner CC applies there.
function stateToPhaseCode(state) {
  if (!state) return null;
  const s = state.toLowerCase();
  if (s.startsWith('rd')) return 'RD';
  if (s.startsWith('fsd')) return 'FSD';
  if (s.startsWith('development')) return 'DEV';
  if (s.startsWith('testing')) return 'TESTING';
  if (s.startsWith('uat')) return 'UAT';
  if (s.startsWith('deployment')) return 'DEPLOYMENT';
  if (s.startsWith('dba deployment')) return 'DBA_DEPLOYMENT';
  if (s.startsWith('observation')) return 'OBSERVATION';
  return null;
}

// Merges CC sources into one ';'-separated list, case-insensitively
// deduped, and never CCs the primary "To" recipient their own address (both
// real bugs seen in production: the same address appearing twice in Cc when
// a user's own cc_email_address happened to equal the CR Owner's address).
function mergeCc(existingCc, extraEmail, primaryEmail) {
  const seen = new Set();
  const parts = [];
  const primaryKey = primaryEmail ? String(primaryEmail).trim().toLowerCase() : null;
  function add(source) {
    if (!source) return;
    String(source).split(';').map(s => s.trim()).filter(Boolean).forEach(addr => {
      const key = addr.toLowerCase();
      if (seen.has(key) || key === primaryKey) return;
      seen.add(key);
      parts.push(addr);
    });
  }
  add(existingCc);
  add(extraEmail);
  return parts.length ? parts.join(';') : null;
}

// Ensures a given event (one function call) emails each distinct address at
// most once — even when two different roles (Process Owner, Requester,
// Approver...) resolve to the same person, which happens routinely in a
// small team/test environment and occasionally in production too. Keeps
// whichever message is offered first; later offers for the same address are
// dropped rather than sent as a near-duplicate.
function oncePerEmail() {
  const seen = new Set();
  return function claim(email) {
    if (!email) return false;
    const key = email.trim().toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  };
}

// Only fetches (and thus only CCs/displays) the CR Owner when the given
// phase is FSD or later.
async function getCrOwnerForPhase(releaseId, phaseCode) {
  if (!isFsdOrLater(phaseCode)) return null;
  return lookup.getCrOwnerInfo(releaseId);
}

// Single, exact-wording assignment notice — used for every "this CR/sub-task
// is now assigned to you" moment (CR create/reassign/auto-reassign, sub-task
// assign/reassign, legacy task assign). kind is 'CR' or 'SUB-TASK'; number is
// the release/task number shown to the recipient; recipient is a lookup
// object with {userId, email, cc, fullName}. extra: {title, parentRelease,
// taskType, assignedBy, assignedDate, phaseCode} — all optional, SUB-TASK-
// only fields simply don't render when omitted (see templates.assignmentTemplate).
async function sendAssignmentMail(kind, number, releaseId, recipient, extra) {
  if (!recipient || !recipient.email) return;
  extra = extra || {};
  try {
    const link = crLink(releaseId);
    const subject = `${kind} ${number} IS ASSIGN TO YOU.`;
    await insertNotification(recipient.userId, subject, `${kind} ${number} has been assigned to you.`, releaseId);
    const crOwner = await getCrOwnerForPhase(releaseId, extra.phaseCode);
    const html = templates.assignmentTemplate({
      kind, number, link, title: extra.title, parentRelease: extra.parentRelease,
      taskType: extra.taskType, assignedBy: extra.assignedBy, assignedDate: extra.assignedDate,
      crOwner: crOwner ? crOwner.fullName : null,
    });
    const cc = mergeCc(recipient.cc, crOwner ? crOwner.email : null, recipient.email);
    await sendMailSafe(recipient.email, cc, subject, html);
  } catch (err) {
    logger.error('[EmailService] sendAssignmentMail failed', { kind, number, releaseId, error: err.message });
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
    const crOwner = await getCrOwnerForPhase(releaseId, phaseCode);
    const ownerCc = crOwner ? crOwner.email : null;
    const ts = timestamp();
    const link = crLink(releaseId);
    const label = phaseLabel(phaseCode);

    const recipients = [];

    if (po && po.email) {
      recipients.push({
        email: po.email, cc: po.cc,
        recipientName: po.fullName,
        message: `The ${label} phase has started for CR ${rel.releaseNumber}. ${triggerName ? triggerName + ' has been assigned as the approver.' : ''}`,
      });
    }

    for (const app of approvers) {
      if (!app.email) continue;
      recipients.push({
        email: app.email, cc: app.cc,
        recipientName: app.fullName,
        message: `A new approval has been assigned to you for CR ${rel.releaseNumber} (${label} phase, Level 1). Please review and take action.`,
        level: 1,
        requesterName: reqInfo ? reqInfo.fullName : '',
        userId: app.userId,
      });
    }

    if (reqInfo && reqInfo.email) {
      recipients.push({
        email: reqInfo.email, cc: reqInfo.cc,
        recipientName: reqInfo.fullName,
        message: `Your Change Request ${rel.releaseNumber} has entered the ${label} phase. ${approvers.length ? 'Current approver: ' + approvers.map(a => a.fullName).join(', ') : 'No approver assigned yet.'}`,
      });
    }

    // One email per distinct address for this event — a Process Owner who is
    // also the Requester (or an approver) for this CR gets only the first,
    // highest-priority message rather than a stack of near-duplicates.
    const claimed = oncePerEmail();
    const uniqueRecipients = recipients.filter(r => claimed(r.email));

    const common = { crNumber: rel.releaseNumber, title: rel.title, moduleName: rel.moduleName, phase: label, timestamp: ts, link, crOwner: crOwner ? crOwner.fullName : null };
    for (const r of uniqueRecipients) {
      let html;
      if (r.level) {
        html = templates.approvalRequiredTemplate({
          ...common, recipientName: r.recipientName, message: r.message, level: r.level, requesterName: r.requesterName || '',
          approveLink: approveLink(releaseId, r.userId), rejectLink: rejectLink(releaseId, r.userId),
        });
      } else {
        html = templates.phaseStartedTemplate({ ...common, recipientName: r.recipientName, message: r.message });
      }
      await sendMailSafe(r.email, mergeCc(r.cc, ownerCc, r.email), r.level ? `Action Required - ${label} Approval` : `${label} Phase Started`, html);
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
    const crOwner = await getCrOwnerForPhase(releaseId, phaseCode);
    const ownerCc = crOwner ? crOwner.email : null;
    const ts = timestamp();
    const link = crLink(releaseId);
    const label = phaseLabel(phaseCode);
    const common = { crNumber: rel.releaseNumber, title: rel.title, moduleName: rel.moduleName, phase: label, timestamp: ts, link, crOwner: crOwner ? crOwner.fullName : null };
    const claimed = oncePerEmail();

    if (po && po.email && claimed(po.email)) {
      await insertNotification(po.userId, `${label} Phase Completed`, `The ${label} phase has been fully approved and completed for CR ${rel.releaseNumber}.`, releaseId);
      const html = templates.phaseCompletedTemplate({
        ...common, recipientName: po.fullName,
        message: `The ${label} phase has been fully approved and completed for CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(po.email, mergeCc(po.cc, ownerCc, po.email), `${label} Phase Completed`, html);
    }

    if (reqInfo && reqInfo.email && claimed(reqInfo.email)) {
      await insertNotification(reqInfo.userId, `${label} Phase Completed`, `The ${label} phase has been completed for your CR ${rel.releaseNumber}.`, releaseId);
      const html = templates.phaseCompletedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `The ${label} phase has been completed for your CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(reqInfo.email, mergeCc(reqInfo.cc, ownerCc, reqInfo.email), `${label} Phase Completed`, html);
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
    const crOwner = await getCrOwnerForPhase(releaseId, phaseCode);
    const ownerCc = crOwner ? crOwner.email : null;
    const ts = timestamp();
    const link = crLink(releaseId);
    const label = phaseLabel(phaseCode);
    const common = { crNumber: rel.releaseNumber, title: rel.title, moduleName: rel.moduleName, phase: label, level, approvedBy: approvedByName, timestamp: ts, link, crOwner: crOwner ? crOwner.fullName : null };
    // One email per distinct address for this whole approval event — a
    // Process Owner who is also the Requester (or the next-level Approver)
    // gets only the first, highest-priority message. This is also what
    // prevents the isFinal branch below from re-notifying someone who
    // already got the Level-Approved message moments earlier in this same call.
    const claimed = oncePerEmail();

    if (po && po.email && claimed(po.email)) {
      const html = templates.approvalCompletedTemplate({
        ...common, recipientName: po.fullName,
        message: `${approvedByName} approved the ${label} Level ${level} task for CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(po.email, mergeCc(po.cc, ownerCc, po.email), `${label} Level ${level} Approved`, html);
    }

    if (reqInfo && reqInfo.email && claimed(reqInfo.email)) {
      await insertNotification(reqInfo.userId, `${label} Level ${level} Approved`, `${approvedByName} approved your ${label} Level ${level} request for CR ${rel.releaseNumber}.`, releaseId);
      const html = templates.approvalCompletedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `${approvedByName} approved your ${label} Level ${level} request for CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(reqInfo.email, mergeCc(reqInfo.cc, ownerCc, reqInfo.email), `${label} Level ${level} Approved`, html);
    }

    // Final level approved — the phase itself is now complete. This is the
    // ONLY place that notifies "Phase Completed" (approvalController.js used
    // to also call sendPhaseCompleted() right after this, unconditionally
    // re-sending the same message to the same two people — removed as a
    // straight duplicate-email bug).
    if (isFinal) {
      if (po && po.email && claimed(po.email)) {
        await insertNotification(po.userId, `${label} Phase Completed`, `The ${label} phase has been fully approved and completed for CR ${rel.releaseNumber}.`, releaseId);
        const html = templates.phaseCompletedTemplate({
          ...common, recipientName: po.fullName, level: undefined,
          message: `The ${label} phase has been fully approved and completed for CR ${rel.releaseNumber}.`,
        });
        await sendMailSafe(po.email, mergeCc(po.cc, ownerCc, po.email), `${label} Phase Completed`, html);
      }
      if (reqInfo && reqInfo.email && claimed(reqInfo.email)) {
        await insertNotification(reqInfo.userId, `${label} Phase Completed`, `The ${label} phase has been completed for your CR ${rel.releaseNumber}.`, releaseId);
        const html = templates.phaseCompletedTemplate({
          ...common, recipientName: reqInfo.fullName, level: undefined,
          message: `The ${label} phase has been completed for your CR ${rel.releaseNumber}.`,
        });
        await sendMailSafe(reqInfo.email, mergeCc(reqInfo.cc, ownerCc, reqInfo.email), `${label} Phase Completed`, html);
      }
    }

    if (nextLevelApproverIds && nextLevelApproverIds.length) {
      // Deliberately NOT gated by `claimed` — this is a genuinely new,
      // actionable "your approval is needed" email, not a restatement of
      // what already went out above. It must still go out even if this
      // approver happens to be the same person as the Process Owner/
      // Requester who already got an FYI in this same call. Only guards
      // against the same next-approver address appearing twice in the list.
      const nextClaimed = oncePerEmail();
      const nextApprovers = await lookup.getUsersEmails(nextLevelApproverIds);
      for (const na of nextApprovers) {
        if (!na.email || !nextClaimed(na.email)) continue;
        const html = templates.approvalRequiredTemplate({
          ...common, recipientName: na.fullName, level: level + 1, requesterName: reqInfo ? reqInfo.fullName : '',
          message: `CR ${rel.releaseNumber} requires your ${label} Level ${level + 1} approval. Previous level approved by ${approvedByName}.`,
          approveLink: approveLink(releaseId, na.userId), rejectLink: rejectLink(releaseId, na.userId),
        });
        await sendMailSafe(na.email, mergeCc(na.cc, ownerCc, na.email), `Action Required - ${label} Level ${level + 1} Approval`, html);
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
    const crOwner = await getCrOwnerForPhase(releaseId, phaseCode);
    const ownerCc = crOwner ? crOwner.email : null;
    const ts = timestamp();
    const link = crLink(releaseId);
    const label = phaseLabel(phaseCode);
    const common = { crNumber: rel.releaseNumber, title: rel.title, moduleName: rel.moduleName, phase: label, rejectedBy: rejectedByName, remarks: remarks || 'No remarks provided', timestamp: ts, link, crOwner: crOwner ? crOwner.fullName : null };
    const claimed = oncePerEmail();

    if (reqInfo && reqInfo.email && claimed(reqInfo.email)) {
      await insertNotification(reqInfo.userId, `${label} Approval Rejected`, `Your ${label} Level ${level} request for CR ${rel.releaseNumber} has been rejected by ${rejectedByName}.`, releaseId);
      const html = templates.approvalRejectedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `Your ${label} Level ${level} request for CR ${rel.releaseNumber} has been rejected by ${rejectedByName}.`,
      });
      await sendMailSafe(reqInfo.email, mergeCc(reqInfo.cc, ownerCc, reqInfo.email), `${label} Approval Rejected`, html);
    }

    if (po && po.email && claimed(po.email)) {
      const html = templates.approvalRejectedTemplate({
        ...common, recipientName: po.fullName,
        message: `${rejectedByName} rejected the ${label} Level ${level} approval for CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(po.email, mergeCc(po.cc, ownerCc, po.email), `${label} Approval Rejected`, html);
    }
  } catch (err) {
    logger.error('[EmailService] sendApprovalRejected failed', { releaseId, phaseCode, error: err.message });
  }
}

async function sendSubtaskAssigned(releaseId, taskNumber, phaseCode, assignedToUserId, createdByUserId, taskTitle) {
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
    const label = phaseLabel(phaseCode);

    // Assignee gets the exact-wording assignment notice, with the sub-task
    // detail columns (Parent Release, Type of Task, Assigned By, Assigned Date) filled in.
    await sendAssignmentMail('SUB-TASK', taskNumber, releaseId, assignedUser, {
      title: taskTitle, parentRelease: rel.releaseNumber, taskType: label,
      assignedBy: creatorUser ? creatorUser.fullName : 'System',
      assignedDate: ts, phaseCode,
    });

    // Creator gets a confirmation that it was assigned — skipped when the
    // creator assigned the task to themselves, since the assignment notice
    // above already told them exactly that (same person, same event).
    const selfAssigned = assignedUser && creatorUser && assignedUser.email &&
      assignedUser.email.toLowerCase() === (creatorUser.email || '').toLowerCase();
    if (creatorUser && creatorUser.email && !selfAssigned) {
      const link = crLink(releaseId);
      const crOwner = await getCrOwnerForPhase(releaseId, phaseCode);
      const html = templates.subtaskAssignedTemplate({
        crNumber: rel.releaseNumber, title: taskTitle, moduleName: rel.moduleName, phase: label,
        taskNumber: taskNumber, assignedBy: creatorUser.fullName,
        recipientName: creatorUser.fullName, timestamp: ts, link,
        crOwner: crOwner ? crOwner.fullName : null,
        message: `Your sub-task on CR ${rel.releaseNumber} (${label} phase) has been assigned to ${assignedUser ? assignedUser.fullName : 'a user'}.`,
      });
      await sendMailSafe(creatorUser.email, mergeCc(creatorUser.cc, crOwner ? crOwner.email : null, creatorUser.email), 'Sub-Task Assigned Successfully', html);
    }
  } catch (err) {
    logger.error('[EmailService] sendSubtaskAssigned failed', { releaseId, taskNumber, error: err.message });
  }
}

async function sendSubtaskCompleted(releaseId, taskId, phaseCode, completedByUserId, taskTitle) {
  try {
    const rel = await lookup.getReleaseInfo(releaseId);
    if (!rel) return;
    const completedBy = await lookup.getUserName(completedByUserId);
    const crOwner = await getCrOwnerForPhase(releaseId, phaseCode);
    const ts = timestamp();
    const link = crLink(releaseId);
    const label = phaseLabel(phaseCode);

    const common = { crNumber: rel.releaseNumber, title: taskTitle, moduleName: rel.moduleName, phase: label,
      taskNumber: `TASK-${taskId}`, completedBy: completedBy || 'Unknown', timestamp: ts, link,
      crOwner: crOwner ? crOwner.fullName : null };

    const reqInfo = await lookup.getRequesterInfo(releaseId);

    if (reqInfo && reqInfo.email) {
      await insertNotification(reqInfo.userId, 'Sub-Task Completed', `${completedBy} has completed the assigned sub-task on CR ${rel.releaseNumber} (${label} phase).`, releaseId);
      const html = templates.subtaskCompletedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `${completedBy} has completed the assigned sub-task on CR ${rel.releaseNumber} (${label} phase).`,
      });
      await sendMailSafe(reqInfo.email, mergeCc(reqInfo.cc, crOwner ? crOwner.email : null, reqInfo.email), 'Sub-Task Completed', html);
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
    const crOwner = await getCrOwnerForPhase(releaseId, 'DEPLOYMENT');
    const ownerCc = crOwner ? crOwner.email : null;
    const ts = timestamp();
    const link = crLink(releaseId);
    const common = { crNumber: rel.releaseNumber, title: rel.title, moduleName: rel.moduleName, timestamp: ts, link, crOwner: crOwner ? crOwner.fullName : null };
    const claimed = oncePerEmail();

    if (reqInfo && reqInfo.email && claimed(reqInfo.email)) {
      await insertNotification(reqInfo.userId, 'Deployment Completed', `Deployment has been completed for your CR ${rel.releaseNumber}.`, releaseId);
      const html = templates.deploymentCompletedTemplate({
        ...common, recipientName: reqInfo.fullName,
        message: `Deployment has been completed for your CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(reqInfo.email, mergeCc(reqInfo.cc, ownerCc, reqInfo.email), 'Deployment Completed', html);
    }

    if (po && po.email && claimed(po.email)) {
      const html = templates.deploymentCompletedTemplate({
        ...common, recipientName: po.fullName,
        message: `Deployment has been completed for CR ${rel.releaseNumber}.`,
      });
      await sendMailSafe(po.email, mergeCc(po.cc, ownerCc, po.email), 'Deployment Completed', html);
    }
  } catch (err) {
    logger.error('[EmailService] sendDeploymentCompleted failed', { releaseId, error: err.message });
  }
}

async function sendCrAssigned(releaseId, assignedToUserId) {
  try {
    const assignee = (await lookup.getUsersEmails([assignedToUserId]))[0];
    if (!assignee || !assignee.email) return;
    const rel = await lookup.getReleaseInfo(releaseId);
    if (!rel) return;
    await sendAssignmentMail('CR', rel.releaseNumber, releaseId, assignee, {
      title: rel.title, phaseCode: stateToPhaseCode(rel.state),
    });
  } catch (err) {
    logger.error('[EmailService] sendCrAssigned failed', { releaseId, assignedToUserId, error: err.message });
  }
}

async function sendSubtaskReassigned(releaseId, taskNumber, phaseCode, assignedToUserId, taskTitle, byUserId) {
  try {
    const assignedUser = (await lookup.getUsersEmails([assignedToUserId]))[0];
    if (!assignedUser || !assignedUser.email) return;
    const [byName, rel] = await Promise.all([
      byUserId ? lookup.getUserName(byUserId) : Promise.resolve(null),
      lookup.getReleaseInfo(releaseId),
    ]);
    await sendAssignmentMail('SUB-TASK', taskNumber, releaseId, assignedUser, {
      title: taskTitle, parentRelease: rel ? rel.releaseNumber : null, taskType: phaseLabel(phaseCode),
      assignedBy: byName || 'System', assignedDate: timestamp(), phaseCode,
    });
  } catch (err) {
    logger.error('[EmailService] sendSubtaskReassigned failed', { releaseId, taskNumber, error: err.message });
  }
}

async function sendLegacyTaskAssigned(releaseId, taskId, taskNumber, phase, assignedToUserId, taskTitle, createdByUserId) {
  try {
    const assignedUser = (await lookup.getUsersEmails([assignedToUserId]))[0];
    if (!assignedUser || !assignedUser.email) return;
    const [byName, rel] = await Promise.all([
      createdByUserId ? lookup.getUserName(createdByUserId) : Promise.resolve(null),
      lookup.getReleaseInfo(releaseId),
    ]);
    // Legacy phase vocabulary (BRD/FSD/Dev/Testing/UAT) — map any FSD-or-
    // later legacy phase to the canonical 'FSD' code so the shared
    // CR-Owner-CC gate (which only knows the release_tasks vocabulary)
    // still applies correctly; the displayed Type of Task keeps the real
    // legacy phase name regardless.
    const gatePhaseCode = isLegacyFsdOrLater(phase) ? 'FSD' : null;
    await sendAssignmentMail('SUB-TASK', taskNumber, releaseId, assignedUser, {
      title: taskTitle, parentRelease: rel ? rel.releaseNumber : null, taskType: phase,
      assignedBy: byName || 'System', assignedDate: timestamp(), phaseCode: gatePhaseCode,
    });
  } catch (err) {
    logger.error('[EmailService] sendLegacyTaskAssigned failed', { releaseId, taskId, error: err.message });
  }
}

async function sendTaskDefaulted(releaseId, taskId, taskNumber, phaseCode, assignedToUserId, ageingDays, taskTitle) {
  try {
    const rel = await lookup.getReleaseInfo(releaseId);
    if (!rel) return;
    const assignedUser = (await lookup.getUsersEmails([assignedToUserId]))[0];
    if (!assignedUser || !assignedUser.email) return;
    const crOwner = await getCrOwnerForPhase(releaseId, phaseCode);
    const ts = timestamp();
    const link = crLink(releaseId);
    const label = phaseLabel(phaseCode);
    const message = `Sub-task ${taskNumber} on CR ${rel.releaseNumber} (${label} phase) is now ${ageingDays} days old and has defaulted its target — please take action.`;
    const notifTitle = 'Task Defaulted: ' + taskNumber;

    // Dedupe: skip if this exact defaulted-notice was already sent for this task.
    const existing = await db.queryOne(
      "SELECT notification_id FROM crms_notifications WHERE user_id=" + parseInt(assignedUser.userId, 10) +
      " AND release_id=" + parseInt(releaseId, 10) + " AND title='" + notifTitle.replace(/'/g, "''") + "' FETCH FIRST 1 ROWS ONLY", {}
    );
    if (existing) return;

    await insertNotification(assignedUser.userId, notifTitle, message, releaseId);
    const html = templates.taskDefaultedTemplate({
      crNumber: rel.releaseNumber, title: taskTitle, moduleName: rel.moduleName, phase: label,
      taskNumber: taskNumber, ageingDays: ageingDays,
      recipientName: assignedUser.fullName, timestamp: ts, link,
      crOwner: crOwner ? crOwner.fullName : null,
    });
    await sendMailSafe(assignedUser.email, mergeCc(assignedUser.cc, crOwner ? crOwner.email : null, assignedUser.email), 'Task Overdue - ' + taskNumber, html);
  } catch (err) {
    logger.error('[EmailService] sendTaskDefaulted failed', { releaseId, taskId, error: err.message });
  }
}

// Resource Bandwidth digest — sends the same week/month heatmap the in-app
// view shows to a fixed recipient list. `data` is exactly the payload
// analyticsController.getResourceBandwidth() returns (weekBuckets,
// monthBuckets, resources) — the caller (bandwidthDigestChecker.js) fetches
// it via the controller directly, so the emailed numbers can never drift
// from what the in-app heatmap shows. No per-recipient personalization —
// everyone on the list gets the same org-wide view.
async function sendBandwidthDigest(recipientEmails, data) {
  if (!recipientEmails || !recipientEmails.length) {
    logger.warn('[EmailService] sendBandwidthDigest skipped — no recipients configured');
    return { success: false, error: 'No recipients configured' };
  }
  try {
    const html = templates.bandwidthDigestTemplate({
      weekBuckets: data.weekBuckets, monthBuckets: data.monthBuckets, resources: data.resources,
      link: `${APP_BASE()}/`,
    });
    return await sendMailSafe(recipientEmails.join(';'), null, 'Resource Bandwidth Digest', html);
  } catch (err) {
    logger.error('[EmailService] sendBandwidthDigest failed', { error: err.message });
    return { success: false, error: err.message };
  }
}

module.exports = {
  insertNotification,
  sendPhaseStarted, sendPhaseCompleted, sendApprovalCompleted, sendApprovalRejected,
  sendSubtaskAssigned, sendSubtaskCompleted, sendDeploymentCompleted,
  sendCrAssigned, sendSubtaskReassigned, sendLegacyTaskAssigned, sendTaskDefaulted,
  sendBandwidthDigest,
};
