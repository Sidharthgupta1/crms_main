'use strict';

const graphClient = require('./graphClient');
const logger = require('../../config/logger');

async function sendEmail(to, subject, htmlBody) {
  if (!to || !to.length) {
    logger.warn('[Mailer] No recipients — skipping');
    return { success: false, error: 'No recipients' };
  }
  const recipients = Array.isArray(to) ? to : [to];
  const validRecipients = recipients.filter(a => a && a.includes('@'));
  if (!validRecipients.length) {
    logger.warn('[Mailer] No valid email addresses — skipping', { original: recipients });
    return { success: false, error: 'No valid email addresses' };
  }
  const result = await graphClient.sendEmail({
    subject,
    htmlBody,
    to: validRecipients,
  });
  if (!result.success) {
    logger.error('[Mailer] Failed to send email', {
      to: validRecipients.join(', '),
      subject,
      error: result.error,
    });
  }
  return result;
}

module.exports = { sendEmail };