'use strict';

const { Client } = require('@microsoft/microsoft-graph-client');
const { ConfidentialClientApplication } = require('@azure/msal-node');
const logger = require('../../config/logger');

let _client = null;
let _cca = null;

function getCredentials() {
  const tenantId = process.env.MS_GRAPH_TENANT_ID;
  const clientId = process.env.MS_GRAPH_CLIENT_ID;
  const clientSecret = process.env.MS_GRAPH_CLIENT_SECRET;
  if (!tenantId || !clientId || !clientSecret) {
    logger.warn('[Graph] MS Graph env vars not configured — email disabled');
    return null;
  }
  return { tenantId, clientId, clientSecret };
}

function getFromAddress() {
  return process.env.MS_GRAPH_FROM_EMAIL || 'crms-noreply@motherson.com';
}
function getFromName() {
  return process.env.MS_GRAPH_FROM_NAME || 'CRMS Notification';
}

async function getAccessToken() {
  const creds = getCredentials();
  if (!creds) return null;
  if (!_cca) {
    _cca = new ConfidentialClientApplication({
      auth: {
        clientId: creds.clientId,
        authority: `https://login.microsoftonline.com/${creds.tenantId}`,
        clientSecret: creds.clientSecret,
      },
    });
  }
  const result = await _cca.acquireTokenByClientCredential({
    scopes: ['https://graph.microsoft.com/.default'],
  });
  logger.info('[Graph] Access token acquired');
  return result.accessToken;
}

async function getAuthenticatedClient() {
  if (_client) return _client;
  _client = Client.initWithMiddleware({
    authProvider: {
      getAccessToken: async () => getAccessToken(),
    },
  });
  return _client;
}

async function sendEmail(message) {
  const client = await getAuthenticatedClient();
  if (!client) {
    logger.warn('[Graph] Email skipped — MS Graph not configured');
    return { success: false, error: 'MS Graph not configured' };
  }
  const fromAddr = getFromAddress();
  const fromName = getFromName();
  const emailPayload = {
    message: {
      subject: message.subject,
      body: { contentType: 'html', content: message.htmlBody },
      toRecipients: message.to.map(addr => ({
        emailAddress: { address: addr },
      })),
    },
    saveToSentItems: false,
  };
  try {
    await client.api(`/users/${fromAddr}/sendMail`).post(emailPayload);
    logger.info('[Graph] Email sent', {
      to: message.to.join(', '),
      subject: message.subject,
    });
    return { success: true };
  } catch (err) {
    const msg = err.message || String(err);
    logger.error('[Graph] Send failed', { error: msg, to: message.to.join(', ') });
    return { success: false, error: msg };
  }
}

module.exports = { sendEmail, getFromAddress, getFromName };