/**
 * Migration: Add instance and email_address columns to crms_users
 * Run: node scripts/add_instance_email_columns.js
 */
require('dotenv').config();
const oracledb = require('oracledb');

async function run() {
  const conn = await oracledb.getConnection({
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    connectionString: process.env.DB_CONNECTION_STRING,
  });
  try {
    // Add instance column (tracks PRIMARY vs SECONDARY origin)
    try {
      await conn.execute(
        "ALTER TABLE crms_users ADD (instance VARCHAR2(20) DEFAULT 'PRIMARY')"
      );
      console.log('✓ Added instance column');
    } catch (e) {
      if (e.errorNum === 1430) console.log('ℹ instance column already exists');
      else throw e;
    }

    // Add email_address column
    try {
      await conn.execute(
        "ALTER TABLE crms_users ADD (email_address VARCHAR2(200))"
      );
      console.log('✓ Added email_address column');
    } catch (e) {
      if (e.errorNum === 1430) console.log('ℹ email_address column already exists');
      else throw e;
    }

    // Set existing rows to PRIMARY
    const result = await conn.execute(
      "UPDATE crms_users SET instance='PRIMARY' WHERE instance IS NULL"
    );
    console.log('✓ Set ' + (result.rowsAffected || 0) + ' existing users to PRIMARY');

    await conn.commit();
    console.log('Migration complete.');
  } finally {
    await conn.close();
  }
}

run().catch(e => { console.error('Migration failed:', e.message); process.exit(1); });
