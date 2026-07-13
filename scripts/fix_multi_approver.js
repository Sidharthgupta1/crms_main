'use strict';
try { require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') }); } catch(e) {}

const oracledb = require('oracledb');
oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;
oracledb.autoCommit = false;

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
    // Step 1: Check if table exists with wrong schema (old version without identity column)
    const checkId = await conn.execute(
      "SELECT identity_column FROM user_tab_columns WHERE table_name = 'CRMS_APPROVAL_FLOW_APPROVERS' AND column_name = 'ID'"
    );
    const needsRecreate = checkId.rows.length > 0 && checkId.rows[0].IDENTITY_COLUMN !== 'YES';

    if (needsRecreate) {
      console.log('Old schema detected (ID is not identity). Recreating table...');
      
      // Drop foreign key constraints first
      await conn.execute('ALTER TABLE crms_approval_flow_approvers DROP CONSTRAINT fk_afa_flow').catch(e => {});
      await conn.execute('ALTER TABLE crms_approval_flow_approvers DROP CONSTRAINT fk_afa_user').catch(e => {});
      await conn.execute('ALTER TABLE crms_approval_flow_approvers DROP CONSTRAINT FK_FA_FLOW').catch(e => {});
      await conn.execute('ALTER TABLE crms_approval_flow_approvers DROP CONSTRAINT FK_FA_USER').catch(e => {});
      
      // Drop indexes
      await conn.execute('DROP INDEX idx_afa_flow').catch(e => {});
      await conn.execute('DROP INDEX idx_afa_user').catch(e => {});
      
      // Drop table
      await conn.execute('DROP TABLE crms_approval_flow_approvers');
      console.log('  DROPPED: old crms_approval_flow_approvers table');
    }

    // Step 2: Check if table exists at all
    const checkExists = await conn.execute(
      "SELECT count(*) AS cnt FROM user_tables WHERE table_name = 'CRMS_APPROVAL_FLOW_APPROVERS'"
    );
    const tableExists = checkExists.rows[0].CNT > 0;

    if (!tableExists) {
      console.log('Creating crms_approval_flow_approvers table...');
      await conn.execute(`
        CREATE TABLE crms_approval_flow_approvers (
          id               NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          flow_id          NUMBER         NOT NULL,
          approver_user_id NUMBER         NOT NULL,
          CONSTRAINT fk_afa_flow FOREIGN KEY (flow_id) REFERENCES crms_approval_flows(flow_id) ON DELETE CASCADE,
          CONSTRAINT fk_afa_user FOREIGN KEY (approver_user_id) REFERENCES crms_users(user_id),
          CONSTRAINT uq_afa_flow_user UNIQUE (flow_id, approver_user_id)
        )
      `);
      await conn.execute('CREATE INDEX idx_afa_flow ON crms_approval_flow_approvers(flow_id)');
      await conn.execute('CREATE INDEX idx_afa_user ON crms_approval_flow_approvers(approver_user_id)');
      console.log('  CREATED: crms_approval_flow_approvers table (with IDENTITY column)');
    } else {
      console.log('  OK: crms_approval_flow_approvers already has correct schema');
    }

    // Step 3: Migrate existing approvers into mapping table
    const migrate = await conn.execute(`
      INSERT INTO crms_approval_flow_approvers (flow_id, approver_user_id)
      SELECT af.flow_id, af.approver_user_id
      FROM crms_approval_flows af
      WHERE af.approver_user_id IS NOT NULL
        AND af.approver_user_id > 0
        AND NOT EXISTS (
          SELECT 1 FROM crms_approval_flow_approvers afa
          WHERE afa.flow_id = af.flow_id AND afa.approver_user_id = af.approver_user_id
        )
    `);
    console.log('  MIGRATED:', migrate.rowsAffected, 'approver rows into mapping table');

    // Step 4: Ensure chk_ra_status constraint includes 'Skipped'
    try {
      const chkConstraint = await conn.execute(
        "SELECT count(*) AS cnt FROM user_constraints WHERE table_name = 'CRMS_RELEASE_APPROVALS' AND constraint_name = 'CHK_RA_STATUS'"
      );
      if (chkConstraint.rows[0].CNT > 0) {
        await conn.execute('ALTER TABLE crms_release_approvals DROP CONSTRAINT chk_ra_status');
        console.log('  DROPPED: old chk_ra_status constraint');
      }
      await conn.execute(`
        ALTER TABLE crms_release_approvals ADD CONSTRAINT chk_ra_status
          CHECK (status IN ('Pending','Approved','Rejected','Skipped'))
      `);
      console.log('  UPDATED: chk_ra_status includes Skipped');
    } catch(e) {
      console.log('  NOTE: chk_ra_status:', e.message);
    }

    await conn.commit();
    console.log('\nDone! All changes applied successfully.');
    console.log('You can now add multiple approvers per level in the module settings.');
  } catch(err) {
    console.error('Error:', err.message);
    try { await conn.rollback(); } catch(e) {}
    process.exit(1);
  } finally {
    try { await conn.close(); } catch(e) {}
  }
}

run();
