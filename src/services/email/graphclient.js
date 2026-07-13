'use strict';

const { Client } = require('@microsoft/microsoft-graph-client');
const { ClientSecretCredential } = require('@azure/identity');
const logger = require('../../config/logger');

let _client = null;
let _tokenExpiresAt = 0;

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
  return process.env.MS_GRAPH_FROM_EMAIL || 'sidharth.gupta@motherson.com';
}
function getFromName() {
  return process.env.MS_GRAPH_FROM_NAME || 'CRMS Email Integration';
}

async function getAuthenticatedClient() {
  const creds = getCredentials();
  if (!creds) return null;
  if (_client && Date.now() < _tokenExpiresAt) return _client;
  const credential = new ClientSecretCredential(
    creds.tenantId,
    creds.clientId,
    creds.clientSecret
  );
  _client = Client.initWithMiddleware({
    authProvider: {
      getAccessToken: async () => {
        const token = await credential.getToken('https://graph.microsoft.com/.default');
        _tokenExpiresAt = token.expiresOn ? token.expiresOn.getTime() : Date.now() + 3600000;
        return token.token;
      },
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