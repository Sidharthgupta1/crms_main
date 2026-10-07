'use strict';

// One-click Approve/Reject straight from the email — per explicit business
// request, no confirmation page, no login: opening the link performs the
// action immediately. That was a deliberate call after flagging the
// trade-off (mail-scanner auto-visits, forwarded emails) — see emailService.js's
// email-action token generation for the mitigation actually used: each link
// is a signed, single-purpose, expiring JWT (not a guessable/reusable plain
// URL), and it re-enters the exact same approve()/reject() business logic
// the authenticated UI uses (including its own state checks), so a second
// click or a stale link naturally no-ops via "already actioned" rather than
// double-approving.

const jwt = require('jsonwebtoken');
const db = require('../config/db');
const logger = require('../config/logger');
const approvalController = require('./approvalController');

const EMAIL_ACTION_SECRET = process.env.EMAIL_ACTION_SECRET || process.env.JWT_SECRET;
const EMAIL_ACTION_EXPIRES_IN = process.env.EMAIL_ACTION_EXPIRES_IN || '7d';

function makeActionToken(payload) {
  return jwt.sign(payload, EMAIL_ACTION_SECRET, { expiresIn: EMAIL_ACTION_EXPIRES_IN });
}

function resultPage(title, message, isError) {
  const color = isError ? '#c62828' : '#2e7d32';
  return `<!DOCTYPE html><html><head><meta charset="UTF-8"><title>${title}</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;background:#f5f5f5;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.card{background:#fff;padding:40px;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,.1);max-width:440px;text-align:center}
h1{color:${color};font-size:22px;margin:0 0 12px}
p{color:#333;font-size:15px;line-height:1.5}
</style></head>
<body><div class="card"><h1>${title}</h1><p>${message}</p></div></body></html>`;
}

async function handleEmailAction(req, res) {
  const { token } = req.params;
  let payload;
  try {
    payload = jwt.verify(token, EMAIL_ACTION_SECRET);
  } catch (err) {
    return res.status(400).send(resultPage('Link Expired or Invalid',
      'This approval link is no longer valid. Please open the CRMS tool to take action.', true));
  }

  const { releaseId, userId, action } = payload;
  if (!releaseId || !userId || (action !== 'approve' && action !== 'reject')) {
    return res.status(400).send(resultPage('Invalid Link', 'This link is malformed.', true));
  }

  let userRow;
  try {
    userRow = await db.queryOne(
      'SELECT user_id, full_name, role FROM crms_users WHERE user_id=' + parseInt(userId, 10) + ' AND is_active=1', {}
    );
  } catch (err) {
    logger.error('[EmailAction] user lookup failed', { error: err.message });
    return res.status(500).send(resultPage('Something Went Wrong', 'Please try again from the CRMS tool.', true));
  }
  if (!userRow) {
    return res.status(400).send(resultPage('Invalid Link', 'User not found or inactive.', true));
  }

  const fakeReq = {
    params: { releaseId: String(releaseId) },
    body: action === 'reject' ? { comments: 'Rejected via email link' } : { comments: '' },
    user: { userId: String(userRow.USER_ID), role: userRow.ROLE, fullName: userRow.FULL_NAME },
  };
  let statusCode = 200;
  let resultBody = null;
  const fakeRes = {
    status(code) { statusCode = code; return this; },
    json(body) { resultBody = body; return this; },
  };
  const fakeNext = (err) => {
    statusCode = 500;
    resultBody = { error: (err && err.message) || 'Something went wrong.' };
    logger.error('[EmailAction] handler passed to next()', { error: resultBody.error });
  };

  try {
    if (action === 'approve') await approvalController.approve(fakeReq, fakeRes, fakeNext);
    else await approvalController.reject(fakeReq, fakeRes, fakeNext);
  } catch (err) {
    logger.error('[EmailAction] handler threw', { action, releaseId, error: err.message });
    return res.status(500).send(resultPage('Something Went Wrong', 'Please try again from the CRMS tool.', true));
  }

  if (statusCode >= 200 && statusCode < 300) {
    logger.info('[EmailAction] completed', { action, releaseId, userId });
    return res.send(resultPage(
      action === 'approve' ? 'Approved' : 'Rejected',
      (resultBody && resultBody.message) || `The request has been ${action === 'approve' ? 'approved' : 'rejected'}.`,
      false
    ));
  }
  logger.warn('[EmailAction] could not complete', { action, releaseId, userId, statusCode, resultBody });
  return res.status(statusCode).send(resultPage(
    'Action Needed',
    (resultBody && resultBody.error) || 'This could not be completed automatically — please open the CRMS tool to finish this action.',
    true
  ));
}

module.exports = { makeActionToken, handleEmailAction };
