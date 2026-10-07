'use strict';

// Sends CRMS mail directly from Node via nodemailer — no Oracle package
// involved. Config is one block of env vars (see .env.example): host,
// port, secure/auth flags, and the from address/name. Replaces the earlier
// Oracle-side transports (Microsoft Graph, then XXMSSL_EMAIL_PKG, then
// UTL_SMTP) — all removed per the user's request to stop depending on
// Oracle grants/ACLs for mail delivery.

const nodemailer = require('nodemailer');
const logger = require('../../config/logger');

let _transport = null;

function fromAddress() {
  return process.env.SMTP_FROM_EMAIL || 'crms-noreply@motherson.com';
}
function fromName() {
  return process.env.SMTP_FROM_NAME || 'CRMS Notification';
}

function getTransport() {
  if (_transport) return _transport;
  const host = process.env.SMTP_HOST;
  if (!host) {
    logger.warn('[SMTP] SMTP_HOST not configured — email disabled');
    return null;
  }
  const port = parseInt(process.env.SMTP_PORT, 10) || 25;
  const secure = String(process.env.SMTP_SECURE).toLowerCase() === 'true';
  const requireAuth = String(process.env.SMTP_REQUIRE_AUTH).toLowerCase() === 'true';

  const opts = { host, port, secure };
  if (requireAuth) {
    opts.auth = { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS };
  }
  _transport = nodemailer.createTransport(opts);
  return _transport;
}

async function sendEmail(message) {
  const transport = getTransport();
  if (!transport) return { success: false, error: 'SMTP not configured' };
  const to = Array.isArray(message.to) ? message.to.join(', ') : message.to;
  if (!to) {
    logger.warn('[SMTP] Email skipped — no recipient');
    return { success: false, error: 'No recipient' };
  }
  try {
    const info = await transport.sendMail({
      from: `"${fromName()}" <${fromAddress()}>`,
      to,
      cc: message.cc || undefined,
      subject: message.subject,
      html: message.htmlBody,
    });
    logger.info('[SMTP] Email sent', { to, cc: message.cc, subject: message.subject, messageId: info.messageId });
    return { success: true };
  } catch (err) {
    const msg = err.message || String(err);
    logger.error('[SMTP] sendMail threw', { to, subject: message.subject, error: msg });
    return { success: false, error: msg };
  }
}

module.exports = { sendEmail };
