'use strict';

/*
 * Builds a dependency-ordered Oracle SQL package from the connected CRMS
 * schema. CRMS_USERS and USER_SESSIONS are intentionally schema-only.
 * Run: node scripts/build_sql2_export.js
 */
require('dotenv').config();

const fs = require('fs');
const path = require('path');
const oracledb = require('oracledb');

oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;
oracledb.fetchAsString = [oracledb.CLOB];

const outputRoot = path.resolve(__dirname, '..', 'sql2');
const schemaOnlyTables = new Set(['CRMS_USERS', 'USER_SESSIONS']);

function sqlString(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function timestampLiteral(date) {
  const iso = date.toISOString();
  return `TO_TIMESTAMP('${iso.slice(0, 23).replace('T', ' ')}', 'YYYY-MM-DD HH24:MI:SS.FF3')`;
}

function clobLiteral(value) {
  const text = String(value);
  if (text.length <= 3000) return `TO_CLOB(${sqlString(text)})`;
  const chunks = [];
  for (let offset = 0; offset < text.length; offset += 3000) {
    chunks.push(`TO_CLOB(${sqlString(text.slice(offset, offset + 3000))})`);
  }
  return chunks.join(' || ');
}

function valueLiteral(value, column) {
  if (value === null || value === undefined) return 'NULL';
  if (value instanceof Date) return timestampLiteral(value);
  if (Buffer.isBuffer(value)) return `HEXTORAW('${value.toString('hex').toUpperCase()}')`;
  if (typeof value === 'number') return Number.isFinite(value) ? String(value) : 'NULL';
  if (column.DATA_TYPE === 'CLOB' || column.DATA_TYPE === 'NCLOB') return clobLiteral(value);
  return sqlString(value);
}

function writeFile(relativePath, content) {
  const target = path.join(outputRoot, relativePath);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, content.replace(/\r?\n/g, '\r\n'), 'utf8');
}

function fileSlug(index, tableName) {
  return `${String(index).padStart(3, '0')}_${tableName.toLowerCase()}.sql`;
}

async function getDdl(connection, objectType, objectName) {
  const result = await connection.execute(
    'SELECT DBMS_METADATA.GET_DDL(:objectType, :objectName) AS DDL FROM dual',
    { objectType, objectName }
  );
  return String(result.rows[0].DDL).trim();
}

function dependencyOrder(tables, relationships) {
  const all = new Set(tables);
  const children = new Map(tables.map((table) => [table, new Set()]));
  const inbound = new Map(tables.map((table) => [table, 0]));

  for (const { CHILD_TABLE, PARENT_TABLE } of relationships) {
    if (!all.has(CHILD_TABLE) || !all.has(PARENT_TABLE) || CHILD_TABLE === PARENT_TABLE) continue;
    if (!children.get(PARENT_TABLE).has(CHILD_TABLE)) {
      children.get(PARENT_TABLE).add(CHILD_TABLE);
      inbound.set(CHILD_TABLE, inbound.get(CHILD_TABLE) + 1);
    }
  }

  const ready = tables.filter((table) => inbound.get(table) === 0).sort();
  const ordered = [];
  while (ready.length) {
    const table = ready.shift();
    ordered.push(table);
    for (const child of [...children.get(table)].sort()) {
      inbound.set(child, inbound.get(child) - 1);
      if (inbound.get(child) === 0) ready.push(child);
    }
    ready.sort();
  }

  // Keep cyclic/self-referencing tables deterministic; their data file is
  // still generated and can be loaded after temporarily disabling its FK.
  return ordered.concat(tables.filter((table) => !ordered.includes(table)).sort());
}

function dependentTables(rootTable, relationships) {
  const children = new Map();
  for (const { CHILD_TABLE, PARENT_TABLE } of relationships) {
    if (!children.has(PARENT_TABLE)) children.set(PARENT_TABLE, new Set());
    children.get(PARENT_TABLE).add(CHILD_TABLE);
  }
  const result = new Set([rootTable]);
  const pending = [rootTable];
  while (pending.length) {
    const parent = pending.shift();
    for (const child of children.get(parent) || []) {
      if (result.has(child)) continue;
      result.add(child);
      pending.push(child);
    }
  }
  return result;
}

async function main() {
  const connection = await oracledb.getConnection({
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    connectionString: process.env.DB_CONNECTION_STRING,
  });

  try {
    await connection.execute(`BEGIN
      DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SQLTERMINATOR', TRUE);
      DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'EMIT_SCHEMA', FALSE);
      DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', FALSE);
      DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE', FALSE);
    END;`);

    const tableRows = await connection.execute(`SELECT table_name
      FROM user_tables
      WHERE table_name LIKE 'CRMS\\_%' ESCAPE '\\' OR table_name = 'USER_SESSIONS'
      ORDER BY table_name`);
    const tables = tableRows.rows.map((row) => row.TABLE_NAME);

    const relationshipRows = await connection.execute(`SELECT child.table_name AS child_table,
        parent.table_name AS parent_table
      FROM user_constraints child
      JOIN user_constraints parent
        ON parent.owner = child.r_owner AND parent.constraint_name = child.r_constraint_name
      WHERE child.constraint_type = 'R'
        AND (child.table_name LIKE 'CRMS\\_%' ESCAPE '\\' OR child.table_name = 'USER_SESSIONS')`);
    const orderedTables = dependencyOrder(tables, relationshipRows.rows);
    const userDependentTables = dependentTables('CRMS_USERS', relationshipRows.rows);
    const dataExcludedTables = new Set([...schemaOnlyTables, ...userDependentTables]);
    const sequenceRows = await connection.execute(`SELECT sequence_name FROM user_sequences
      WHERE sequence_name LIKE 'CRMS\\_%' ESCAPE '\\' ORDER BY sequence_name`);

    // sql2 is generated output owned by this script. Rebuild it from scratch
    // so stale scripts cannot be accidentally executed.
    fs.rmSync(outputRoot, { recursive: true, force: true });
    fs.mkdirSync(outputRoot, { recursive: true });
    writeFile('README.md', `# CRMS database replication package

Generated from ${process.env.DB_CONNECTION_STRING} on ${new Date().toISOString()}.

Run \`00_run_all.sql\` in SQL*Plus, SQLcl, or Oracle SQL Developer while connected to the target schema.
The package creates the CRMS tables in foreign-key dependency order, loads the configuration data that is independent of users, and then creates supporting objects.

\`CRMS_USERS\` is deliberately created without rows so the target environment can add its own users.
\`USER_SESSIONS\` is also structure-only: it contains refresh-token/session state and must not be copied between environments.

Rows from tables that depend on \`CRMS_USERS\` are not loaded, because copying them without their referenced users would violate foreign keys and produce a broken database. Their table structures are fully included. After users are added in the target environment, create new releases, approvals, tasks, memberships, and other operational records there.
`);

    const runner = [
      'WHENEVER SQLERROR EXIT SQL.SQLCODE',
      'SET DEFINE OFF',
      'SET SQLBLANKLINES ON',
      '',
      'PROMPT Creating CRMS tables...',
    ];

    if (sequenceRows.rows.length) {
      const sequenceStatements = ['-- Application sequences'];
      
      const drops = [
        'DECLARE',
        '  PROCEDURE drop_seq(seq_name IN VARCHAR2) IS',
        '  BEGIN',
        '    EXECUTE IMMEDIATE \'DROP SEQUENCE "\' || seq_name || \'"\';',
        '  EXCEPTION',
        '    WHEN OTHERS THEN',
        '      IF SQLCODE != -2289 THEN RAISE; END IF;',
        '  END;',
        'BEGIN'
      ];
      for (const row of sequenceRows.rows) {
        drops.push(`  drop_seq('${row.SEQUENCE_NAME}');`);
      }
      drops.push('END;', '/');
      
      sequenceStatements.push(drops.join('\n'));

      for (const row of sequenceRows.rows) {
        sequenceStatements.push(await getDdl(connection, 'SEQUENCE', row.SEQUENCE_NAME));
      }
      writeFile('01_sequences.sql', `${sequenceStatements.join('\n\n')}\n`);
      runner.push('@@01_sequences.sql');
    }

    for (let index = 0; index < orderedTables.length; index += 1) {
      const table = orderedTables[index];
      const filename = fileSlug(index + 1, table);
      const ddl = await getDdl(connection, 'TABLE', table);
      // Primary-key and unique constraints create their own indexes as part of
      // CREATE TABLE. Export only standalone indexes to avoid ORA-00955.
      const indexRows = await connection.execute(`SELECT i.index_name FROM user_indexes i
        WHERE i.table_name = :tableName
          AND i.generated = 'N'
          AND NOT EXISTS (
            SELECT 1 FROM user_constraints c
            WHERE c.table_name = i.table_name
              AND c.index_name = i.index_name
              AND c.constraint_type IN ('P', 'U')
          )
        ORDER BY i.index_name`, { tableName: table });
      const indexDdls = [];
      for (const row of indexRows.rows) indexDdls.push(await getDdl(connection, 'INDEX', row.INDEX_NAME));
      writeFile(path.join('01_schema', filename), `-- ${table}\n${ddl}\n${indexDdls.join('\n\n')}${indexDdls.length ? '\n' : ''}`);
      runner.push(`@@01_schema/${filename}`);
    }

    runner.push('', 'PROMPT Loading CRMS data...');
    for (let index = 0; index < orderedTables.length; index += 1) {
      const table = orderedTables[index];
      if (dataExcludedTables.has(table)) continue;
      const filename = fileSlug(index + 1, table);
      const columnResult = await connection.execute(`SELECT column_name, data_type, identity_column
        FROM user_tab_columns WHERE table_name = :tableName ORDER BY column_id`, { tableName: table });
      const columns = columnResult.rows;
      const identityColumns = columns.filter((column) => column.IDENTITY_COLUMN === 'YES');
      const rows = await connection.execute(`SELECT * FROM "${table}"`);
      const columnNames = columns.map((column) => `"${column.COLUMN_NAME}"`).join(', ');
      const statements = [
        `-- Data for ${table}. Generated rows: ${rows.rows.length}`,
        'SET DEFINE OFF',
      ];
      for (const identityColumn of identityColumns) {
        const columnName = identityColumn.COLUMN_NAME;
        statements.push(`ALTER TABLE "${table}" MODIFY ("${columnName}" GENERATED BY DEFAULT AS IDENTITY);`);
      }
      for (const row of rows.rows) {
        const values = columns.map((column) => valueLiteral(row[column.COLUMN_NAME], column)).join(', ');
        statements.push(`INSERT INTO "${table}" (${columnNames}) VALUES (${values});`);
      }
      // Explicit identity values preserve foreign-key relationships. Advance
      // the target's identity generator afterwards so future inserts do not
      // collide with the imported values. START WITH LIMIT VALUE is the
      // supported mechanism; Oracle does not permit altering its hidden
      // system-generated sequence directly.
      for (const identityColumn of identityColumns) {
        const columnName = identityColumn.COLUMN_NAME;
        statements.push(`ALTER TABLE "${table}" MODIFY ("${columnName}" GENERATED ALWAYS AS IDENTITY (START WITH LIMIT VALUE));`);
      }
      statements.push('COMMIT;', '');
      writeFile(path.join('02_data', filename), statements.join('\n'));
      runner.push(`@@02_data/${filename}`);
    }

    runner.push('', 'PROMPT Creating views, triggers, procedures, and jobs...');
    const objectFiles = [];
    const viewRows = await connection.execute(`SELECT view_name FROM user_views
      WHERE view_name LIKE 'VW\\_%' ESCAPE '\\' ORDER BY view_name`);
    for (const row of viewRows.rows) {
      const filename = `view_${row.VIEW_NAME.toLowerCase()}.sql`;
      writeFile(path.join('03_objects', filename), `-- ${row.VIEW_NAME}\n${await getDdl(connection, 'VIEW', row.VIEW_NAME)}\n`);
      objectFiles.push(filename);
    }

    const triggerRows = await connection.execute(`SELECT trigger_name FROM user_triggers
      WHERE table_name LIKE 'CRMS\\_%' ESCAPE '\\' OR table_name = 'USER_SESSIONS'
      ORDER BY trigger_name`);
    for (const row of triggerRows.rows) {
      const filename = `trigger_${row.TRIGGER_NAME.toLowerCase()}.sql`;
      writeFile(path.join('03_objects', filename), `-- ${row.TRIGGER_NAME}\n${await getDdl(connection, 'TRIGGER', row.TRIGGER_NAME)}\n`);
      objectFiles.push(filename);
    }

    const procedureRows = await connection.execute(`SELECT object_name, object_type FROM user_procedures
      WHERE object_name LIKE 'CRMS\\_%' ESCAPE '\\' ORDER BY object_type, object_name`);
    for (const row of procedureRows.rows) {
      const filename = `${row.OBJECT_TYPE.toLowerCase()}_${row.OBJECT_NAME.toLowerCase()}.sql`;
      writeFile(path.join('03_objects', filename), `-- ${row.OBJECT_NAME}\n${await getDdl(connection, row.OBJECT_TYPE, row.OBJECT_NAME)}\n`);
      objectFiles.push(filename);
    }

    for (const filename of objectFiles) runner.push(`@@03_objects/${filename}`);
    runner.push('', 'PROMPT CRMS replication package completed.', 'EXIT SUCCESS');
    writeFile('00_run_all.sql', `${runner.join('\n')}\n`);

    writeFile('manifest.json', JSON.stringify({
      sourceConnection: process.env.DB_CONNECTION_STRING,
      tablesInExecutionOrder: orderedTables,
      schemaOnlyTables: [...schemaOnlyTables],
      dataTables: orderedTables.filter((table) => !dataExcludedTables.has(table)),
      dataExcludedBecauseUsersAreEmpty: orderedTables.filter((table) =>
        userDependentTables.has(table) && !schemaOnlyTables.has(table)),
      sequences: sequenceRows.rows.map((row) => row.SEQUENCE_NAME),
      supportingObjects: objectFiles,
    }, null, 2));

    console.log(`Generated sql2 package with ${orderedTables.length} table schemas, ${orderedTables.length - dataExcludedTables.size} data scripts, ${sequenceRows.rows.length} sequences, and ${objectFiles.length} supporting-object scripts.`);
  } finally {
    await connection.close();
  }
}

main().catch((error) => {
  console.error('SQL export failed:', error.message);
  process.exitCode = 1;
});
