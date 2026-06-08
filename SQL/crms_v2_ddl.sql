-- ============================================================
-- CRMS V2 DDL — Complete Phase-Based Workflow
-- Run as: APPS user on ebs_MSWILDEV
-- Drops and recreates module/approval/phase tables for new flow
-- ============================================================
SET ECHO OFF
SET SERVEROUTPUT ON SIZE 1000000
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE

BEGIN
  DBMS_OUTPUT.PUT_LINE('CRMS V2 DDL — Starting');
  DBMS_OUTPUT.PUT_LINE('Time: ' || TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS'));
END;
/

-- ============================================================
-- Step 1: Update state constraint on crms_releases
-- New 17-state lifecycle
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_constraints
   WHERE table_name='CRMS_RELEASES' AND constraint_name='CHK_RELEASE_STATE';
  IF v > 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases DROP CONSTRAINT chk_release_state';
    DBMS_OUTPUT.PUT_LINE('  DROPPED : old chk_release_state');
  END IF;
END;
/

DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_constraints
   WHERE table_name='CRMS_RELEASES' AND constraint_name='CHK_RELEASE_STATE';
  IF v = 0 THEN
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
    DBMS_OUTPUT.PUT_LINE('  CREATED : chk_release_state (V2 — 28 states)');
  END IF;
END;
/

-- ============================================================
-- Step 2: Drop old module/approval tables (clean rebuild)
-- ============================================================
DECLARE
  PROCEDURE drop_if(p_tbl VARCHAR2) IS
    v NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v FROM user_tables WHERE table_name=UPPER(p_tbl);
    IF v > 0 THEN
      EXECUTE IMMEDIATE 'DROP TABLE ' || p_tbl || ' CASCADE CONSTRAINTS';
      DBMS_OUTPUT.PUT_LINE('  DROPPED : ' || p_tbl);
    END IF;
  END;
BEGIN
  drop_if('CRMS_RELEASE_APPROVALS');
  drop_if('CRMS_APPROVAL_FLOWS');
  drop_if('CRMS_MODULE_USERS');
  drop_if('CRMS_MODULE_GROUPS');
  drop_if('CRMS_MODULES');
END;
/

-- ============================================================
-- Step 3: Create CRMS_MODULES
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_MODULES';
  IF v = 0 THEN
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
-- Step 4: CRMS_PHASE_GROUPS
-- Maps which assignment group handles each phase for a module
-- phase_code: DRAFT, RD, FSD, DEV, TESTING, UAT, DEPLOYMENT
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_PHASE_GROUPS';
  IF v = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_phase_groups (
        phase_group_id  NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_id       NUMBER         NOT NULL
            CONSTRAINT fk_pg_module REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        phase_code      VARCHAR2(20)   NOT NULL
            CONSTRAINT chk_pg_phase CHECK (phase_code IN (
              ''DRAFT'',''RD'',''FSD'',''DEV'',''TESTING'',''UAT'',''DEPLOYMENT''
            )),
        group_id        NUMBER         NOT NULL
            CONSTRAINT fk_pg_group REFERENCES crms_assignment_groups(group_id),
        created_at      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_phase_group UNIQUE (module_id, phase_code)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_pg_module ON crms_phase_groups(module_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_phase_groups');
  END IF;
END;
/

-- ============================================================
-- Step 5: CRMS_PHASE_TEMPLATES
-- Default downloadable templates per phase per module
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_PHASE_TEMPLATES';
  IF v = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_phase_templates (
        template_id   NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_id     NUMBER         NOT NULL
            CONSTRAINT fk_pt_module REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        phase_code    VARCHAR2(20)   NOT NULL
            CONSTRAINT chk_pt_phase CHECK (phase_code IN (''RD'',''FSD'',''DEV'',''TESTING'',''UAT'',''DEPLOYMENT'')),
        file_name     VARCHAR2(500)  NOT NULL,
        file_type     VARCHAR2(200),
        file_data     CLOB           NOT NULL,
        uploaded_by   NUMBER         NOT NULL
            CONSTRAINT fk_pt_user REFERENCES crms_users(user_id),
        created_at    TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_phase_template UNIQUE (module_id, phase_code)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_pt_module ON crms_phase_templates(module_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_phase_templates');
  END IF;
END;
/

-- ============================================================
-- Step 6: CRMS_APPROVAL_FLOWS (rebuilt — per phase per module)
-- phase_code: DRAFT, RD, FSD, DEPLOYMENT
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_APPROVAL_FLOWS';
  IF v = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_approval_flows (
        flow_id           NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_id         NUMBER         NOT NULL
            CONSTRAINT fk_af_module REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        phase_code        VARCHAR2(20)   NOT NULL
            CONSTRAINT chk_af_phase CHECK (phase_code IN (''DRAFT'',''RD'',''FSD'',''DEPLOYMENT'')),
        level_order       NUMBER(2)      NOT NULL,
        approver_user_id  NUMBER         NOT NULL
            CONSTRAINT fk_af_user REFERENCES crms_users(user_id),
        auto_approve      NUMBER(1)      DEFAULT 0 NOT NULL,
        created_at        TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_af_level UNIQUE (module_id, phase_code, level_order)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_af_module ON crms_approval_flows(module_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_approval_flows');
  END IF;
END;
/

-- ============================================================
-- Step 7: CRMS_RELEASE_APPROVALS (rebuilt — tracks per-release approval)
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_RELEASE_APPROVALS';
  IF v = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_release_approvals (
        approval_id       NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_id        NUMBER         NOT NULL
            CONSTRAINT fk_ra_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        module_id         NUMBER         NOT NULL
            CONSTRAINT fk_ra_module REFERENCES crms_modules(module_id),
        phase_code        VARCHAR2(20)   NOT NULL,
        level_order       NUMBER(2)      NOT NULL,
        approver_user_id  NUMBER         NOT NULL
            CONSTRAINT fk_ra_approver REFERENCES crms_users(user_id),
        status            VARCHAR2(10)   DEFAULT ''Pending'' NOT NULL
            CONSTRAINT chk_ra_status CHECK (status IN (''Pending'',''Approved'',''Rejected'')),
        comments          VARCHAR2(2000),
        actioned_at       TIMESTAMP,
        created_at        TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_ra_release ON crms_release_approvals(release_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_ra_approver ON crms_release_approvals(approver_user_id,status)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_release_approvals');
  END IF;
END;
/

-- ============================================================
-- Step 8: CRMS_RELEASE_TASKS (replaces crms_tasks for phase tasks)
-- Each phase auto-generates tasks for group members
-- ============================================================
-- Note: crms_tasks still exists for manual sub-tasks
-- crms_release_tasks = auto-generated phase tasks with upload tracking
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_RELEASE_TASKS';
  IF v = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_release_tasks (
        task_id           NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        task_number       VARCHAR2(20)   NOT NULL,
        release_id        NUMBER         NOT NULL
            CONSTRAINT fk_rt_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        phase_code        VARCHAR2(20)   NOT NULL,
        assigned_to       NUMBER         NOT NULL
            CONSTRAINT fk_rt_assignee REFERENCES crms_users(user_id),
        state             VARCHAR2(10)   DEFAULT ''Open'' NOT NULL
            CONSTRAINT chk_rt_state CHECK (state IN (''Open'',''Closed'')),
        template_downloaded NUMBER(1)    DEFAULT 0,
        attachment_id     NUMBER,
        closed_by         NUMBER
            CONSTRAINT fk_rt_closedby REFERENCES crms_users(user_id),
        closed_at         TIMESTAMP,
        created_at        TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_rt_number UNIQUE (task_number)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rt_release ON crms_release_tasks(release_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rt_assignee ON crms_release_tasks(assigned_to)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_release_tasks');
  END IF;
END;
/

-- ============================================================
-- Step 9: Add module_id and current_approval_level to crms_releases
-- (if not already there from V1)
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns
   WHERE table_name='CRMS_RELEASES' AND column_name='MODULE_ID';
  IF v = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases ADD module_id NUMBER';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases ADD CONSTRAINT fk_rel_module
      FOREIGN KEY (module_id) REFERENCES crms_modules(module_id)';
    DBMS_OUTPUT.PUT_LINE('  ADDED   : crms_releases.module_id');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_releases.module_id');
  END IF;
END;
/
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns
   WHERE table_name='CRMS_RELEASES' AND column_name='CURRENT_APPROVAL_LEVEL';
  IF v = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases ADD current_approval_level NUMBER DEFAULT 0';
    DBMS_OUTPUT.PUT_LINE('  ADDED   : crms_releases.current_approval_level');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_releases.current_approval_level');
  END IF;
END;
/

-- ============================================================
-- Step 10: Sequence for release tasks
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_sequences WHERE sequence_name='CRMS_RTASK_SEQ';
  IF v = 0 THEN
    EXECUTE IMMEDIATE 'CREATE SEQUENCE crms_rtask_seq START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_rtask_seq');
  END IF;
END;
/

-- ============================================================
-- Seed: Default module
-- ============================================================
MERGE INTO crms_modules t
USING (SELECT 'Oracle EBS' AS nm, 'Default Oracle EBS module' AS ds FROM dual) s
ON (t.module_name = s.nm)
WHEN NOT MATCHED THEN INSERT (module_name, description) VALUES (s.nm, s.ds);

COMMIT;

BEGIN
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('CRMS V2 DDL complete.');
  DBMS_OUTPUT.PUT_LINE('Tables: crms_modules, crms_phase_groups, crms_phase_templates,');
  DBMS_OUTPUT.PUT_LINE('        crms_approval_flows, crms_release_approvals, crms_release_tasks');
  DBMS_OUTPUT.PUT_LINE('States: 28 total from Draft to Closed');
END;
/

-- ============================================================
-- Add phase_code and task_id to crms_attachments (if not exists)
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
COMMIT;
