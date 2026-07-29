'use strict';

/**
 * Upgrades the existing USER_SESSIONS table to the schema expected by the
 * application. This migration is additive and can be safely re-run.
 *
 * Run: node scripts/migrate_user_sessions.js
 */
require('dotenv').config();

const oracledb = require('oracledb');
oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;

const columns = [
  ['REFRESH_TOKEN_HASH', 'VARCHAR2(64)'],
  ['DEVICE_ID', 'VARCHAR2(64)'],
  ['DEVICE_NAME', 'VARCHAR2(200)'],
  ['BROWSER', 'VARCHAR2(100)'],
  ['OPERATING_SYSTEM', 'VARCHAR2(100)'],
  ['IP_ADDRESS', 'VARCHAR2(45)'],
  ['USER_AGENT', 'VARCHAR2(500)'],
  ['STATUS', "VARCHAR2(10) DEFAULT 'ACTIVE'"],
  ['CREATED_AT', 'TIMESTAMP DEFAULT SYSTIMESTAMP'],
  ['LAST_ACTIVITY', 'TIMESTAMP DEFAULT SYSTIMESTAMP'],
  ['SESSION_EXPIRES_AT', 'TIMESTAMP'],
  ['REVOKED_AT', 'TIMESTAMP'],
];

async function main() {
  let connection;
  try {
    connection = await oracledb.getConnection({
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      connectionString: process.env.DB_CONNECTION_STRING,
    });

    const table = await connection.execute(
      "SELECT COUNT(*) AS COUNT FROM user_tables WHERE table_name = 'USER_SESSIONS'"
    );
    if (table.rows[0].COUNT === 0) {
      throw new Error('USER_SESSIONS does not exist. Run SQL/crms_user_sessions_ddl.sql first.');
    }

    const result = await connection.execute(
      "SELECT column_name FROM user_tab_columns WHERE table_name = 'USER_SESSIONS'"
    );
    const existing = new Set(result.rows.map((row) => row.COLUMN_NAME));

    for (const [name, definition] of columns) {
      if (existing.has(name)) continue;
      await connection.execute(`ALTER TABLE user_sessions ADD (${name.toLowerCase()} ${definition})`);
      console.log(`Added USER_SESSIONS.${name}`);
    }

    // Some legacy deployments contain mandatory fields that are not part of
    // the current session INSERT. Give those fields safe defaults so both
    // schema versions remain compatible.
    const legacyDefaults = {
      INSTANCE: "DEFAULT 'PRIMARY'",
      ABSOLUTE_EXPIRES_AT: "DEFAULT SYSTIMESTAMP + INTERVAL '8' HOUR",
    };
    for (const [name, defaultValue] of Object.entries(legacyDefaults)) {
      if (!existing.has(name)) continue;
      await connection.execute(`ALTER TABLE user_sessions MODIFY (${name.toLowerCase()} ${defaultValue})`);
      console.log(`Set USER_SESSIONS.${name} ${defaultValue}.`);
    }

    // Older deployments allowed only ACTIVE/REVOKED. The application also
    // writes EXPIRED during cleanup, so align the legacy constraint first.
    const oldConstraint = await connection.execute(
      "SELECT constraint_name FROM user_constraints WHERE table_name = 'USER_SESSIONS' AND constraint_name = 'CHK_SESSION_STATUS'"
    );
    if (oldConstraint.rows.length > 0) {
      await connection.execute('ALTER TABLE user_sessions DROP CONSTRAINT chk_session_status');
      console.log('Updated legacy CHK_SESSION_STATUS constraint.');
    }

    // Existing rows from a pre-session-management table need valid values.
    await connection.execute(`UPDATE user_sessions
      SET status = NVL(status, 'ACTIVE'),
          created_at = NVL(created_at, SYSTIMESTAMP),
          last_activity = NVL(last_activity, SYSTIMESTAMP),
          session_expires_at = NVL(session_expires_at, SYSTIMESTAMP - INTERVAL '1' SECOND)`);
    await connection.execute(`UPDATE user_sessions
      SET status = 'EXPIRED'
      WHERE status NOT IN ('ACTIVE', 'REVOKED', 'EXPIRED')`);
    await connection.execute(`ALTER TABLE user_sessions ADD CONSTRAINT chk_session_status
      CHECK (status IN ('ACTIVE', 'REVOKED', 'EXPIRED'))`);

    await connection.execute(
      'CREATE INDEX idx_sessions_expires ON user_sessions(session_expires_at)'
    ).catch((error) => {
      if (error.errorNum !== 955) throw error;
    });

    // Exercise the same statement used by the one-minute application cleanup.
    const cleanup = await connection.execute(`UPDATE user_sessions
      SET status = 'EXPIRED', revoked_at = SYSTIMESTAMP
      WHERE status = 'ACTIVE'
        AND (session_expires_at < SYSTIMESTAMP
             OR (CAST(SYSTIMESTAMP AS DATE) - CAST(last_activity AS DATE)) * 1440 > 30)`);

    await connection.commit();
    const verification = await connection.execute(
      'SELECT COUNT(*) AS ROW_COUNT FROM user_sessions WHERE session_expires_at IS NOT NULL'
    );
    const applicationColumns = [
      'SESSION_ID', 'USER_ID', 'REFRESH_TOKEN_HASH', 'DEVICE_ID', 'DEVICE_NAME',
      'BROWSER', 'OPERATING_SYSTEM', 'IP_ADDRESS', 'USER_AGENT', 'STATUS',
      'CREATED_AT', 'LAST_ACTIVITY', 'SESSION_EXPIRES_AT', 'REVOKED_AT',
      ...Object.keys(legacyDefaults),
    ];
    const requiredLegacyColumns = await connection.execute(`SELECT column_name
      FROM user_tab_columns
      WHERE table_name = 'USER_SESSIONS'
        AND nullable = 'N'
        AND data_default IS NULL`);
    const unsupported = requiredLegacyColumns.rows
      .map((row) => row.COLUMN_NAME)
      .filter((name) => !applicationColumns.includes(name));
    if (unsupported.length > 0) {
      console.warn(`Required legacy columns without defaults: ${unsupported.join(', ')}`);
    }
    console.log(`Session cleanup query succeeded; expired ${cleanup.rowsAffected || 0} stale session(s).`);
    console.log(`Verified SESSION_EXPIRES_AT on ${verification.rows[0].ROW_COUNT} existing row(s).`);
    console.log('USER_SESSIONS migration complete.');
  } finally {
    if (connection) await connection.close();
  }
}

main().catch((error) => {
  console.error('USER_SESSIONS migration failed:', error.message);
  process.exitCode = 1;
});
