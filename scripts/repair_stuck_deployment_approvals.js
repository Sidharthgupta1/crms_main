'use strict';
/**
 * Repairs CRs where deployment approval was committed but state transition
 * failed due to missing Observation Phase in chk_release_state.
 * Run: node scripts/repair_stuck_deployment_approvals.js
 */
try { require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') }); } catch (e) {}

const oracledb = require('oracledb');
oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;
oracledb.autoCommit = false;

(async function () {
  const conn = await oracledb.getConnection({
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    connectionString: process.env.DB_CONNECTION_STRING,
  });

  const rows = await conn.execute(
    "SELECT r.release_id, r.release_number, r.state, r.module_id, r.current_approval_level " +
    "FROM crms_releases r " +
    "WHERE r.is_deleted = 0 AND r.state LIKE 'Deployment Approval%'"
  );

  let repaired = 0;
  for (const rel of rows.rows || []) {
    const rid = rel.RELEASE_ID;
    const mid = rel.MODULE_ID;

    const maxLevel = await conn.execute(
      "SELECT NVL(MAX(level_order), 0) AS max_lvl FROM crms_approval_flows " +
      "WHERE module_id = " + mid + " AND phase_code = 'DEPLOYMENT'"
    );
    const required = Number(maxLevel.rows[0].MAX_LVL) || 0;
    if (!required) continue;

    const approved = await conn.execute(
      "SELECT COUNT(DISTINCT level_order) AS cnt FROM crms_release_approvals " +
      "WHERE release_id = " + rid + " AND phase_code = 'DEPLOYMENT' AND status = 'Approved'"
    );
    const approvedCount = Number(approved.rows[0].CNT) || 0;

    if (approvedCount < required) {
      console.log('Skip', rel.RELEASE_NUMBER, '- only', approvedCount, 'of', required, 'levels approved');
      continue;
    }

    const curState = rel.STATE;
    await conn.execute(
      "UPDATE crms_releases SET state = 'Observation Phase', current_approval_level = 0, updated_at = SYSDATE " +
      "WHERE release_id = " + rid
    );
    await conn.execute(
      "INSERT INTO crms_release_history(release_id, action, from_state, to_state, changed_by) " +
      "VALUES(" + rid + ", 'State Change', '" + curState.replace(/'/g, "''") + "', 'Observation Phase', 1)"
    );
    console.log('Repaired', rel.RELEASE_NUMBER, curState, '-> Observation Phase');
    repaired++;
  }

  await conn.commit();
  console.log('Done. Repaired', repaired, 'release(s).');
  await conn.close();
})().catch(async function (e) {
  console.error('Repair failed:', e.message);
  process.exit(1);
});
