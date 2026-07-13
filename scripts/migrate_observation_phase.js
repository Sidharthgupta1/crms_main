'use strict';
/**
 * Adds "Observation Phase" (and Deployment Approval L* states) to chk_release_state.
 * Run: node scripts/migrate_observation_phase.js
 */
try { require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') }); } catch (e) {}

const oracledb = require('oracledb');
oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;
oracledb.autoCommit = false;

const RELEASE_STATES = [
  'Draft',
  'Draft Awaiting Approval L1', 'Draft Awaiting Approval L2', 'Draft Awaiting Approval L3',
  'Draft Awaiting Approval L4', 'Draft Awaiting Approval L5',
  'RD Phase',
  'RD Awaiting Approval L1', 'RD Awaiting Approval L2', 'RD Awaiting Approval L3',
  'RD Awaiting Approval L4', 'RD Awaiting Approval L5',
  'FSD Phase',
  'FSD Awaiting Approval L1', 'FSD Awaiting Approval L2', 'FSD Awaiting Approval L3',
  'FSD Awaiting Approval L4', 'FSD Awaiting Approval L5',
  'Development Phase',
  'Testing Phase',
  'UAT Phase',
  'Deployment Phase',
  'Deployment Approval L1', 'Deployment Approval L2', 'Deployment Approval L3',
  'Deployment Approval L4', 'Deployment Approval L5',
  'Deployment Awaiting Approval L1', 'Deployment Awaiting Approval L2',
  'Deployment Awaiting Approval L3', 'Deployment Awaiting Approval L4',
  'Deployment Awaiting Approval L5',
  'Observation Phase',
  'On Hold', 'Closed', 'Cancelled',
];

async function run() {
  const dbUser = process.env.DB_USER;
  const dbPass = process.env.DB_PASSWORD;
  const dbConn = process.env.DB_CONNECTION_STRING;
  if (!dbUser || !dbPass || !dbConn) {
    console.error('Missing DB_USER / DB_PASSWORD / DB_CONNECTION_STRING in .env');
    process.exit(1);
  }

  const conn = await oracledb.getConnection({ user: dbUser, password: dbPass, connectionString: dbConn });
  console.log('Connected to Oracle');

  try {
    const constraints = await conn.execute(
      "SELECT constraint_name FROM user_constraints " +
      "WHERE table_name = 'CRMS_RELEASES' AND constraint_type = 'C'"
    );
    const toDrop = (constraints.rows || []).filter(function (row) {
      return /RELEASE_STATE/i.test(row.CONSTRAINT_NAME);
    });
    if (!toDrop.length) {
      console.log('No existing chk_release_state constraint found — will create fresh.');
    }

    for (const row of toDrop) {
      const name = row.CONSTRAINT_NAME;
      await conn.execute('ALTER TABLE crms_releases DROP CONSTRAINT ' + name);
      console.log('Dropped constraint:', name);
    }

    const col = await conn.execute(
      "SELECT data_length FROM user_tab_columns " +
      "WHERE table_name = 'CRMS_RELEASES' AND column_name = 'STATE'"
    );
    const len = col.rows && col.rows[0] ? Number(col.rows[0].DATA_LENGTH) : 30;
    if (len < 60) {
      await conn.execute('ALTER TABLE crms_releases MODIFY state VARCHAR2(60) NOT NULL');
      console.log('Expanded crms_releases.state to VARCHAR2(60)');
    }

    const histCols = await conn.execute(
      "SELECT column_name, data_length FROM user_tab_columns " +
      "WHERE table_name = 'CRMS_RELEASE_HISTORY' AND column_name IN ('FROM_STATE','TO_STATE')"
    );
    for (const row of histCols.rows || []) {
      if (Number(row.DATA_LENGTH) < 60) {
        await conn.execute(
          'ALTER TABLE crms_release_history MODIFY ' + row.COLUMN_NAME + ' VARCHAR2(60)'
        );
        console.log('Expanded crms_release_history.' + row.COLUMN_NAME + ' to VARCHAR2(60)');
      }
    }

    const inList = RELEASE_STATES.map(function (s) { return "'" + s.replace(/'/g, "''") + "'"; }).join(',');
    await conn.execute(
      'ALTER TABLE crms_releases ADD CONSTRAINT chk_release_state CHECK (state IN (' + inList + '))'
    );
    console.log('Created chk_release_state with Observation Phase');

    await conn.commit();
    console.log('Migration complete.');
  } catch (err) {
    await conn.rollback();
    console.error('Migration failed:', err.message);
    process.exit(1);
  } finally {
    await conn.close();
  }
}

run();
