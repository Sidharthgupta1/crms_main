-- ============================================================
-- CRMS V2 DDL — Phase-Based Workflow with Sub-Tasks
-- Run as: APPS user on ebs_MSWILDEV
-- SQL> @crms_v2_ddl.sql
-- ============================================================
SET ECHO OFF
SET SERVEROUTPUT ON SIZE 1000000
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE

BEGIN
  DBMS_OUTPUT.PUT_LINE('============================================');
  DBMS_OUTPUT.PUT_LINE('CRMS V2 DDL — Starting');
  DBMS_OUTPUT.PUT_LINE('Time: '||TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS'));
  DBMS_OUTPUT.PUT_LINE('============================================');
END;
/

-- ============================================================
-- STEP 1: Safety check (no drops — existing data is preserved)
-- ============================================================
-- NOTE: This script only CREATES tables that don't exist yet.
-- Running it again is safe — it will not wipe any data.
BEGIN
  DBMS_OUTPUT.PUT_LINE('  INFO: Creating missing tables only. Existing data preserved.');
END;
/

-- ============================================================
-- STEP 2: Update state constraint — full lifecycle
-- Draft → Draft Approval → RD → RD Approval → FSD → FSD Approval
-- → Development → Testing → UAT → Deployment Approval → Deployment → Closed
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_constraints
   WHERE table_name='CRMS_RELEASES' AND constraint_name='CHK_RELEASE_STATE';
  IF v>0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases DROP CONSTRAINT chk_release_state';
    DBMS_OUTPUT.PUT_LINE('  DROPPED : old chk_release_state');
  END IF;
END;
/
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_constraints
   WHERE table_name='CRMS_RELEASES' AND constraint_name='CHK_RELEASE_STATE';
  IF v=0 THEN
    EXECUTE IMMEDIATE q'[ALTER TABLE crms_releases ADD CONSTRAINT chk_release_state CHECK (state IN (
      'Draft',
      'Draft Awaiting Approval L1','Draft Awaiting Approval L2','Draft Awaiting Approval L3',
      'Draft Awaiting Approval L4','Draft Awaiting Approval L5',
      'RD Phase',
      'RD Awaiting Approval L1','RD Awaiting Approval L2','RD Awaiting Approval L3',
      'RD Awaiting Approval L4','RD Awaiting Approval L5',
      'FSD Phase',
      'FSD Awaiting Approval L1','FSD Awaiting Approval L2','FSD Awaiting Approval L3',
      'FSD Awaiting Approval L4','FSD Awaiting Approval L5',
      'Development Phase',
      'Testing Phase',
      'UAT Phase',
      'Deployment Awaiting Approval L1','Deployment Awaiting Approval L2',
      'Deployment Awaiting Approval L3','Deployment Awaiting Approval L4',
      'Deployment Awaiting Approval L5',
      'Deployment Phase',
      'On Hold','Closed','Cancelled'
    ))]';
    DBMS_OUTPUT.PUT_LINE('  CREATED : chk_release_state V2');
  END IF;
END;
/

-- ============================================================
-- STEP 3: Add module_id + current_approval_level to crms_releases
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns WHERE table_name='CRMS_RELEASES' AND column_name='MODULE_ID';
  IF v=0 THEN EXECUTE IMMEDIATE 'ALTER TABLE crms_releases ADD module_id NUMBER';
    DBMS_OUTPUT.PUT_LINE('  ADDED   : crms_releases.module_id'); END IF;
END;
/
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns WHERE table_name='CRMS_RELEASES' AND column_name='CURRENT_APPROVAL_LEVEL';
  IF v=0 THEN EXECUTE IMMEDIATE 'ALTER TABLE crms_releases ADD current_approval_level NUMBER DEFAULT 0';
    DBMS_OUTPUT.PUT_LINE('  ADDED   : crms_releases.current_approval_level'); END IF;
END;
/

-- ============================================================
-- STEP 4: CRMS_MODULES
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_MODULES';
  IF v=0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_modules (
        module_id    NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_name  VARCHAR2(200)  NOT NULL,
        description  VARCHAR2(500),
        is_active    NUMBER(1)      DEFAULT 1 NOT NULL,
        created_at   TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_module_name UNIQUE (module_name)
      )';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_modules');
  END IF;
END;
/

-- ============================================================
-- STEP 5: CRMS_PHASE_GROUPS
-- Which assignment group handles each phase for a module
-- Phases: DRAFT, RD, FSD, DEV, TESTING, UAT, DEPLOYMENT
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_PHASE_GROUPS';
  IF v=0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_phase_groups (
        phase_group_id NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_id      NUMBER         NOT NULL
            CONSTRAINT fk_pg_module REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        phase_code     VARCHAR2(20)   NOT NULL
            CONSTRAINT chk_pg_phase CHECK (phase_code IN (
              ''DRAFT'',''RD'',''FSD'',''DEV'',''TESTING'',''UAT'',''DEPLOYMENT'')),
        group_id       NUMBER         NOT NULL
            CONSTRAINT fk_pg_group REFERENCES crms_assignment_groups(group_id),
        created_at     TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_phase_group UNIQUE (module_id, phase_code)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_pg_module ON crms_phase_groups(module_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_phase_groups');
  END IF;
END;
/

-- ============================================================
-- STEP 6: CRMS_PHASE_TEMPLATES
-- Admin uploads default template per phase (RD only — FSD has no template)
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_PHASE_TEMPLATES';
  IF v=0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_phase_templates (
        template_id  NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_id    NUMBER         NOT NULL
            CONSTRAINT fk_pt_module REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        phase_code   VARCHAR2(20)   NOT NULL
            CONSTRAINT chk_pt_phase CHECK (phase_code IN (''RD'')),
        file_name    VARCHAR2(500)  NOT NULL,
        file_type    VARCHAR2(200),
        file_data    CLOB           NOT NULL,
        uploaded_by  NUMBER         NOT NULL
            CONSTRAINT fk_pt_user REFERENCES crms_users(user_id),
        created_at   TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_phase_template UNIQUE (module_id, phase_code)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_pt_module ON crms_phase_templates(module_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_phase_templates (RD only)');
  END IF;
END;
/

-- ============================================================
-- STEP 7: CRMS_APPROVAL_FLOWS
-- Approval levels per phase per module
-- Approval phases: DRAFT, RD, FSD, DEPLOYMENT
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_APPROVAL_FLOWS';
  IF v=0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_approval_flows (
        flow_id          NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_id        NUMBER         NOT NULL
            CONSTRAINT fk_af_module REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        phase_code       VARCHAR2(20)   NOT NULL
            CONSTRAINT chk_af_phase CHECK (phase_code IN (''DRAFT'',''RD'',''FSD'',''DEPLOYMENT'')),
        level_order      NUMBER(2)      NOT NULL,
        approver_user_id NUMBER         NOT NULL
            CONSTRAINT fk_af_user REFERENCES crms_users(user_id),
        auto_approve     NUMBER(1)      DEFAULT 0 NOT NULL,
        created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_af_level UNIQUE (module_id, phase_code, level_order)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_af_module ON crms_approval_flows(module_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_approval_flows');
  END IF;
END;
/

-- ============================================================
-- STEP 8: CRMS_RELEASE_APPROVALS
-- Per-release approval tracking
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_RELEASE_APPROVALS';
  IF v=0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_release_approvals (
        approval_id      NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_id       NUMBER         NOT NULL
            CONSTRAINT fk_ra_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        module_id        NUMBER         NOT NULL,
        phase_code       VARCHAR2(20)   NOT NULL,
        level_order      NUMBER(2)      NOT NULL,
        approver_user_id NUMBER         NOT NULL
            CONSTRAINT fk_ra_approver REFERENCES crms_users(user_id),
        status           VARCHAR2(10)   DEFAULT ''Pending'' NOT NULL
            CONSTRAINT chk_ra_status CHECK (status IN (''Pending'',''Approved'',''Rejected'')),
        comments         VARCHAR2(2000),
        actioned_at      TIMESTAMP,
        created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_ra_release  ON crms_release_approvals(release_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_ra_approver ON crms_release_approvals(approver_user_id,status)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_release_approvals');
  END IF;
END;
/

-- ============================================================
-- STEP 9: CRMS_RELEASE_TASKS
-- Sub-tasks per phase — mirror the parent release lifecycle
-- phase_code: RD, FSD, DEV, TESTING, UAT, DEPLOYMENT
-- Each sub-task gets unique RTSK number
-- RD: download template + upload required to close
-- FSD/DEV/TESTING/UAT/DEPLOYMENT: upload required to close (no template)
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_RELEASE_TASKS';
  IF v=0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_release_tasks (
        task_id              NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        task_number          VARCHAR2(20)   NOT NULL,
        release_id           NUMBER         NOT NULL
            CONSTRAINT fk_rt_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        phase_code           VARCHAR2(20)   NOT NULL
            CONSTRAINT chk_rt_phase CHECK (phase_code IN (
              ''RD'',''FSD'',''DEV'',''TESTING'',''UAT'',''DEPLOYMENT'')),
        assigned_to          NUMBER         NOT NULL
            CONSTRAINT fk_rt_assignee REFERENCES crms_users(user_id),
        state                VARCHAR2(10)   DEFAULT ''Open'' NOT NULL
            CONSTRAINT chk_rt_state CHECK (state IN (''Open'',''Closed'')),
        template_downloaded  NUMBER(1)      DEFAULT 0,
        upload_attachment_id NUMBER,
        short_description    VARCHAR2(500),
        closed_by            NUMBER
            CONSTRAINT fk_rt_closedby REFERENCES crms_users(user_id),
        closed_at            TIMESTAMP,
        created_at           TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_rt_number UNIQUE (task_number)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rt_release  ON crms_release_tasks(release_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rt_assignee ON crms_release_tasks(assigned_to)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rt_phase    ON crms_release_tasks(release_id,phase_code)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_release_tasks');
  END IF;
END;
/

-- ============================================================
-- STEP 10: Add phase_code + task_id to crms_attachments
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns WHERE table_name='CRMS_ATTACHMENTS' AND column_name='PHASE_CODE';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_attachments ADD phase_code VARCHAR2(20)';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_attachments ADD task_id NUMBER';
    DBMS_OUTPUT.PUT_LINE('  ADDED   : crms_attachments.phase_code, task_id');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_attachments.phase_code');
  END IF;
END;
/

-- ============================================================
-- STEP 11: Sequence for release sub-tasks (RTSK prefix)
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_sequences WHERE sequence_name='CRMS_RTASK_SEQ';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'CREATE SEQUENCE crms_rtask_seq START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_rtask_seq');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_rtask_seq');
  END IF;
END;
/

-- ============================================================
-- SEED: Default module
-- ============================================================
MERGE INTO crms_modules t
USING (SELECT 'Oracle EBS' AS nm, 'Default Oracle EBS module' AS ds FROM dual) s
ON (t.module_name=s.nm)
WHEN NOT MATCHED THEN INSERT (module_name,description) VALUES (s.nm,s.ds);

COMMIT;

DECLARE v NUMBER;
BEGIN
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM crms_modules' INTO v;
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('============================================');
  DBMS_OUTPUT.PUT_LINE('CRMS V2 DDL COMPLETE');
  DBMS_OUTPUT.PUT_LINE('Tables created:');
  DBMS_OUTPUT.PUT_LINE('  crms_modules          — business modules');
  DBMS_OUTPUT.PUT_LINE('  crms_phase_groups     — group per phase per module');
  DBMS_OUTPUT.PUT_LINE('  crms_phase_templates  — RD template (admin uploads)');
  DBMS_OUTPUT.PUT_LINE('  crms_approval_flows   — DRAFT/RD/FSD/DEPLOYMENT levels');
  DBMS_OUTPUT.PUT_LINE('  crms_release_approvals— per-release approval tracking');
  DBMS_OUTPUT.PUT_LINE('  crms_release_tasks    — RTSK sub-tasks per phase');
  DBMS_OUTPUT.PUT_LINE('Modules seeded: '||v);
  DBMS_OUTPUT.PUT_LINE('============================================');
END;
/

-- ============================================================
-- Add missing columns to crms_release_tasks (run if not exists)
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns WHERE table_name='CRMS_RELEASE_TASKS' AND column_name='PLANNED_START_DATE';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_tasks ADD planned_start_date DATE';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_tasks ADD planned_end_date DATE';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_tasks ADD actual_start_date DATE';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_tasks ADD actual_end_date DATE';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_tasks ADD priority VARCHAR2(1)';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_tasks ADD description CLOB';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_tasks ADD reason_for_reject VARCHAR2(500)';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_tasks ADD assignment_group_id NUMBER';
    DBMS_OUTPUT.PUT_LINE('  ADDED: planned_start_date, planned_end_date, priority, description, etc to crms_release_tasks');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  EXISTS: crms_release_tasks columns already added');
  END IF;
  -- Add assignment_group_id index if missing
  BEGIN
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rt_ag ON crms_release_tasks(assignment_group_id)';
    DBMS_OUTPUT.PUT_LINE('  INDEX   : idx_rt_ag created');
  EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/
COMMIT;
