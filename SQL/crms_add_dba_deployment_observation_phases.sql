-- ============================================================
-- CRMS — Add DBA_DEPLOYMENT and OBSERVATION phases
-- Run as APPS user in SQL Developer
-- Idempotent: safe to run multiple times
-- ============================================================
SET SERVEROUTPUT ON
SET DEFINE OFF

-- ============================================================
-- 1. Update CHECK constraint on CRMS_PHASE_GROUPS
-- Include DBA_DEPLOYMENT and OBSERVATION
-- ============================================================
BEGIN
  FOR c IN (SELECT constraint_name FROM user_constraints
             WHERE table_name='CRMS_PHASE_GROUPS' AND constraint_type='C'
               AND UPPER(search_condition) LIKE '%PHASE_CODE%') LOOP
    EXECUTE IMMEDIATE 'ALTER TABLE crms_phase_groups DROP CONSTRAINT '||c.constraint_name;
    DBMS_OUTPUT.PUT_LINE('Dropped: '||c.constraint_name);
  END LOOP;
END;
/
ALTER TABLE crms_phase_groups ADD CONSTRAINT chk_pg_phase CHECK (phase_code IN (
  'DRAFT','RD','FSD','DEV','TESTING','UAT','DEPLOYMENT','DBA_DEPLOYMENT','OBSERVATION'
));
DBMS_OUTPUT.PUT_LINE('Updated: chk_pg_phase');

-- ============================================================
-- 2. Update CHECK constraint on CRMS_PHASE_TEMPLATES
-- ============================================================
BEGIN
  FOR c IN (SELECT constraint_name FROM user_constraints
             WHERE table_name='CRMS_PHASE_TEMPLATES' AND constraint_type='C'
               AND UPPER(search_condition) LIKE '%PHASE_CODE%') LOOP
    EXECUTE IMMEDIATE 'ALTER TABLE crms_phase_templates DROP CONSTRAINT '||c.constraint_name;
    DBMS_OUTPUT.PUT_LINE('Dropped: '||c.constraint_name);
  END LOOP;
END;
/
ALTER TABLE crms_phase_templates ADD CONSTRAINT chk_pt_phase CHECK (phase_code IN (
  'RD','FSD','DEV','TESTING','UAT','DEPLOYMENT','DBA_DEPLOYMENT','OBSERVATION'
));
DBMS_OUTPUT.PUT_LINE('Updated: chk_pt_phase');

-- ============================================================
-- 3. Update CHECK constraint on CRMS_APPROVAL_FLOWS
-- ============================================================
BEGIN
  FOR c IN (SELECT constraint_name FROM user_constraints
             WHERE table_name='CRMS_APPROVAL_FLOWS' AND constraint_type='C'
               AND UPPER(search_condition) LIKE '%PHASE_CODE%') LOOP
    EXECUTE IMMEDIATE 'ALTER TABLE crms_approval_flows DROP CONSTRAINT '||c.constraint_name;
    DBMS_OUTPUT.PUT_LINE('Dropped: '||c.constraint_name);
  END LOOP;
END;
/
ALTER TABLE crms_approval_flows ADD CONSTRAINT chk_af_phase CHECK (phase_code IN (
  'DRAFT','RD','FSD','DEPLOYMENT','DBA_DEPLOYMENT','OBSERVATION'
));
DBMS_OUTPUT.PUT_LINE('Updated: chk_af_phase');

-- ============================================================
-- 4. Update CHECK constraint on CRMS_COMPANY_GROUP_PHASE_MAP
-- ============================================================
BEGIN
  FOR c IN (SELECT constraint_name FROM user_constraints
             WHERE table_name='CRMS_COMPANY_GROUP_PHASE_MAP' AND constraint_type='C'
               AND UPPER(search_condition) LIKE '%PHASE_CODE%') LOOP
    EXECUTE IMMEDIATE 'ALTER TABLE crms_company_group_phase_map DROP CONSTRAINT '||c.constraint_name;
    DBMS_OUTPUT.PUT_LINE('Dropped: '||c.constraint_name);
  END LOOP;
END;
/
ALTER TABLE crms_company_group_phase_map ADD CONSTRAINT chk_cgpm_phase CHECK (phase_code IN (
  'ALL','RD','FSD','DEV','TESTING','UAT','DEPLOYMENT','DBA_DEPLOYMENT','OBSERVATION'
));
DBMS_OUTPUT.PUT_LINE('Updated: chk_cgpm_phase');

-- ============================================================
-- 5. Update CHECK constraint on CRMS_RELEASE_TASKS (if not already by code)
-- Skip if already dropped/recreated by releaseController.js on startup
-- ============================================================
BEGIN
  FOR c IN (SELECT constraint_name FROM user_constraints
             WHERE table_name='CRMS_RELEASE_TASKS' AND constraint_type='C'
               AND UPPER(search_condition) LIKE '%PHASE_CODE%') LOOP
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_tasks DROP CONSTRAINT '||c.constraint_name;
    DBMS_OUTPUT.PUT_LINE('Dropped: '||c.constraint_name);
  END LOOP;
END;
/
ALTER TABLE crms_release_tasks ADD CONSTRAINT chk_rt_phase CHECK (phase_code IN (
  'RD','FSD','DEV','TESTING','UAT','DEPLOYMENT','DBA_DEPLOYMENT','OBSERVATION'
));
DBMS_OUTPUT.PUT_LINE('Updated: chk_rt_phase');

-- ============================================================
-- 6. Insert phase groups for DBA_DEPLOYMENT and OBSERVATION
--    for every module that already has a DEPLOYMENT phase group
-- ============================================================
INSERT INTO crms_phase_groups (module_id, phase_code, group_id)
SELECT m.module_id, 'DBA_DEPLOYMENT', pg.group_id
FROM crms_modules m
JOIN crms_phase_groups pg ON pg.module_id = m.module_id AND pg.phase_code = 'DEPLOYMENT'
WHERE NOT EXISTS (
  SELECT 1 FROM crms_phase_groups t
  WHERE t.module_id = m.module_id AND t.phase_code = 'DBA_DEPLOYMENT'
);
DBMS_OUTPUT.PUT_LINE('Inserted: crms_phase_groups for DBA_DEPLOYMENT (' || SQL%ROWCOUNT || ' rows)');

INSERT INTO crms_phase_groups (module_id, phase_code, group_id)
SELECT m.module_id, 'OBSERVATION', pg.group_id
FROM crms_modules m
JOIN crms_phase_groups pg ON pg.module_id = m.module_id AND pg.phase_code = 'DEPLOYMENT'
WHERE NOT EXISTS (
  SELECT 1 FROM crms_phase_groups t
  WHERE t.module_id = m.module_id AND t.phase_code = 'OBSERVATION'
);
DBMS_OUTPUT.PUT_LINE('Inserted: crms_phase_groups for OBSERVATION (' || SQL%ROWCOUNT || ' rows)');

-- ============================================================
-- 7. Insert company group phase map entries for DBA_DEPLOYMENT and OBSERVATION
--    Duplicate existing DEPLOYMENT mappings
-- ============================================================
INSERT INTO crms_company_group_phase_map (company_id, service_id, group_id, phase_code)
SELECT cgpm.company_id, cgpm.service_id, cgpm.group_id, 'DBA_DEPLOYMENT'
FROM crms_company_group_phase_map cgpm
WHERE cgpm.phase_code = 'DEPLOYMENT'
  AND NOT EXISTS (
    SELECT 1 FROM crms_company_group_phase_map t
    WHERE t.company_id = cgpm.company_id
      AND t.service_id = cgpm.service_id
      AND t.group_id = cgpm.group_id
      AND t.phase_code = 'DBA_DEPLOYMENT'
  );
DBMS_OUTPUT.PUT_LINE('Inserted: crms_company_group_phase_map for DBA_DEPLOYMENT (' || SQL%ROWCOUNT || ' rows)');

INSERT INTO crms_company_group_phase_map (company_id, service_id, group_id, phase_code)
SELECT cgpm.company_id, cgpm.service_id, cgpm.group_id, 'OBSERVATION'
FROM crms_company_group_phase_map cgpm
WHERE cgpm.phase_code = 'DEPLOYMENT'
  AND NOT EXISTS (
    SELECT 1 FROM crms_company_group_phase_map t
    WHERE t.company_id = cgpm.company_id
      AND t.service_id = cgpm.service_id
      AND t.group_id = cgpm.group_id
      AND t.phase_code = 'OBSERVATION'
  );
DBMS_OUTPUT.PUT_LINE('Inserted: crms_company_group_phase_map for OBSERVATION (' || SQL%ROWCOUNT || ' rows)');

-- ============================================================
-- 8. Insert approval groups for DBA_DEPLOYMENT and OBSERVATION
--    Duplicate existing DEPLOYMENT approval group entries
-- ============================================================
INSERT INTO crms_approval_groups (company_name, service_name, module_id, group_id, phase_code, level_order)
SELECT ag.company_name, ag.service_name, ag.module_id, ag.group_id, 'DBA_DEPLOYMENT', ag.level_order
FROM crms_approval_groups ag
WHERE ag.phase_code = 'DEPLOYMENT'
  AND NOT EXISTS (
    SELECT 1 FROM crms_approval_groups t
    WHERE NVL(t.company_name, 'NULL') = NVL(ag.company_name, 'NULL')
      AND NVL(t.service_name, 'NULL') = NVL(ag.service_name, 'NULL')
      AND (t.module_id = ag.module_id OR (t.module_id IS NULL AND ag.module_id IS NULL))
      AND t.group_id = ag.group_id
      AND t.phase_code = 'DBA_DEPLOYMENT'
  );
DBMS_OUTPUT.PUT_LINE('Inserted: crms_approval_groups for DBA_DEPLOYMENT (' || SQL%ROWCOUNT || ' rows)');

INSERT INTO crms_approval_groups (company_name, service_name, module_id, group_id, phase_code, level_order)
SELECT ag.company_name, ag.service_name, ag.module_id, ag.group_id, 'OBSERVATION', ag.level_order
FROM crms_approval_groups ag
WHERE ag.phase_code = 'DEPLOYMENT'
  AND NOT EXISTS (
    SELECT 1 FROM crms_approval_groups t
    WHERE NVL(t.company_name, 'NULL') = NVL(ag.company_name, 'NULL')
      AND NVL(t.service_name, 'NULL') = NVL(ag.service_name, 'NULL')
      AND (t.module_id = ag.module_id OR (t.module_id IS NULL AND ag.module_id IS NULL))
      AND t.group_id = ag.group_id
      AND t.phase_code = 'OBSERVATION'
  );
DBMS_OUTPUT.PUT_LINE('Inserted: crms_approval_groups for OBSERVATION (' || SQL%ROWCOUNT || ' rows)');

-- ============================================================
-- 9. Insert phase reviewers for DBA_DEPLOYMENT and OBSERVATION
--    Duplicate existing DEPLOYMENT reviewers for each module
-- ============================================================
INSERT INTO crms_phase_reviewers (module_id, phase_code, group_id, user_id)
SELECT pr.module_id, 'DBA_DEPLOYMENT', pr.group_id, pr.user_id
FROM crms_phase_reviewers pr
WHERE pr.phase_code = 'DEPLOYMENT'
  AND NOT EXISTS (
    SELECT 1 FROM crms_phase_reviewers t
    WHERE t.module_id = pr.module_id
      AND t.phase_code = 'DBA_DEPLOYMENT'
      AND t.group_id = pr.group_id
      AND t.user_id = pr.user_id
  );
DBMS_OUTPUT.PUT_LINE('Inserted: crms_phase_reviewers for DBA_DEPLOYMENT (' || SQL%ROWCOUNT || ' rows)');

INSERT INTO crms_phase_reviewers (module_id, phase_code, group_id, user_id)
SELECT pr.module_id, 'OBSERVATION', pr.group_id, pr.user_id
FROM crms_phase_reviewers pr
WHERE pr.phase_code = 'DEPLOYMENT'
  AND NOT EXISTS (
    SELECT 1 FROM crms_phase_reviewers t
    WHERE t.module_id = pr.module_id
      AND t.phase_code = 'OBSERVATION'
      AND t.group_id = pr.group_id
      AND t.user_id = pr.user_id
  );
DBMS_OUTPUT.PUT_LINE('Inserted: crms_phase_reviewers for OBSERVATION (' || SQL%ROWCOUNT || ' rows)');

-- ============================================================
-- 10. Insert phase process owners for DBA_DEPLOYMENT
--     (OBSERVATION does not typically need a process owner since it closes)
--     Duplicate existing DEPLOYMENT process owner for each module
-- ============================================================
INSERT INTO crms_phase_process_owners (module_id, phase_code, group_id, user_id)
SELECT po.module_id, 'DBA_DEPLOYMENT', po.group_id, po.user_id
FROM crms_phase_process_owners po
WHERE po.phase_code = 'DEPLOYMENT'
  AND NOT EXISTS (
    SELECT 1 FROM crms_phase_process_owners t
    WHERE t.module_id = po.module_id
      AND t.phase_code = 'DBA_DEPLOYMENT'
  );
DBMS_OUTPUT.PUT_LINE('Inserted: crms_phase_process_owners for DBA_DEPLOYMENT (' || SQL%ROWCOUNT || ' rows)');

-- ============================================================
-- 11. Update CRMS_RELEASE_PHASE_GROUPS (no inserts needed — created on demand)
--     Already has VARCHAR2(20) phase_code — no CHECK constraints to update
-- ============================================================

COMMIT;
DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('Migration complete: DBA_DEPLOYMENT and OBSERVATION phases added.');
