'use strict';

// Sends the Resource Bandwidth heatmap (same data as the in-app view) to a
// fixed recipient list on a schedule — entirely env-driven since the
// schedule isn't finalized yet ("may vary, not decided") and recipients are
// a hand-picked list rather than a role-derived one. Everything here is
// configurable in .env without a code change:
//
//   BANDWIDTH_DIGEST_RECIPIENTS   ';'-or-','-separated email list. Empty
//                                  (default) = digest is OFF — the checker
//                                  ticks but never sends.
//   BANDWIDTH_DIGEST_FREQUENCY    'weekly' | 'monthly' | 'both'. Default
//                                  'weekly'. Only matters once recipients
//                                  are set.
//   BANDWIDTH_DIGEST_DAY          0-6 (Sun-Sat), default 1 (Monday) — the
//                                  weekly send day.
//   BANDWIDTH_DIGEST_HOUR         0-23, default 8 — the local hour (server
//                                  time) both weekly and monthly sends fire.
//   BANDWIDTH_DIGEST_DAY_OF_MONTH 1-28, default 1 — the monthly send day.
//
// Dedup is an in-memory "already sent this period" marker (reset on process
// restart) rather than a DB row — this is a broadcast digest, not a
// per-item notification, so at most a duplicate send after a restart within
// the same hour, not a correctness issue.

const logger = require('../config/logger');

let lastWeeklySentKey = null;
let lastMonthlySentKey = null;

function getRecipients() {
  const raw = process.env.BANDWIDTH_DIGEST_RECIPIENTS || '';
  return raw.split(/[;,]/).map(function(s) { return s.trim(); }).filter(Boolean);
}
function getFrequency() { return (process.env.BANDWIDTH_DIGEST_FREQUENCY || 'weekly').toLowerCase(); }
function getDay() { const n = parseInt(process.env.BANDWIDTH_DIGEST_DAY, 10); return isNaN(n) ? 1 : n; }
function getHour() { const n = parseInt(process.env.BANDWIDTH_DIGEST_HOUR, 10); return isNaN(n) ? 8 : n; }
function getDayOfMonth() { const n = parseInt(process.env.BANDWIDTH_DIGEST_DAY_OF_MONTH, 10); return isNaN(n) ? 1 : n; }

function isoWeekKey(d) {
  const t = new Date(d);
  t.setHours(0, 0, 0, 0);
  t.setDate(t.getDate() + 3 - ((t.getDay() + 6) % 7)); // nearest Thursday
  const week1 = new Date(t.getFullYear(), 0, 4);
  const weekNo = 1 + Math.round(((t - week1) / 86400000 - 3 + ((week1.getDay() + 6) % 7)) / 7);
  return t.getFullYear() + '-W' + weekNo;
}
function monthKey(d) { return d.getFullYear() + '-' + (d.getMonth() + 1); }

async function sendDigest() {
  const recipients = getRecipients();
  if (!recipients.length) {
    logger.info('[BandwidthDigest] no BANDWIDTH_DIGEST_RECIPIENTS configured — skipping');
    return;
  }
  const ctrl = require('../controllers/analyticsController');
  let data = null;
  const fakeReq = { query: {} };
  const fakeRes = { status() { return this; }, json(b) { data = b; return this; } };
  await ctrl.getResourceBandwidth(fakeReq, fakeRes, function(err) {
    logger.error('[BandwidthDigest] getResourceBandwidth failed', { error: err && err.message });
  });
  if (!data) return;

  const emailSvc = require('./emailService');
  const result = await emailSvc.sendBandwidthDigest(recipients, data);
  if (result && result.success) {
    logger.info('[BandwidthDigest] sent', { recipients: recipients.length });
  } else {
    logger.warn('[BandwidthDigest] send failed', { error: result && result.error });
  }
}

async function tick() {
  try {
    const freq = getFrequency();
    const now = new Date();
    const hour = now.getHours();
    if (hour !== getHour()) return;

    if ((freq === 'weekly' || freq === 'both') && now.getDay() === getDay()) {
      const key = isoWeekKey(now);
      if (key !== lastWeeklySentKey) {
        lastWeeklySentKey = key;
        await sendDigest();
      }
    }
    if ((freq === 'monthly' || freq === 'both') && now.getDate() === getDayOfMonth()) {
      const key = monthKey(now);
      if (key !== lastMonthlySentKey) {
        lastMonthlySentKey = key;
        await sendDigest();
      }
    }
  } catch (err) {
    logger.error('[BandwidthDigest] tick failed', { error: err.message });
  }
}

function start() {
  const ONE_HOUR = 60 * 60 * 1000;
  setInterval(function() { tick().catch(function() {}); }, ONE_HOUR);
  tick().catch(function() {}); // also check immediately, in case the server started mid-hour on the send day
  logger.info('[BandwidthDigest] scheduled — checks hourly; recipients ' +
    (getRecipients().length ? getRecipients().length + ' configured' : 'NOT configured (off)'));
}

module.exports = { start, tick, sendDigest };
