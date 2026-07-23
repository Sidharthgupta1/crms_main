-- ============================================================
-- MOTHERSON CRMS — Unified Master DDL Schema Creation Script
-- Run as: APPS user or DB owner in Oracle SQL Developer / SQL*Plus
-- ============================================================
SET ECHO OFF
SET SERVEROUTPUT ON SIZE 1000000
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE

DECLARE
  v_count NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('===========================================');
  DBMS_OUTPUT.PUT_LINE('CRMS Master DDL Migration — Starting');
  DBMS_OUTPUT.PUT_LINE('User   : ' || SYS_CONTEXT('USERENV','SESSION_USER'));
  DBMS_OUTPUT.PUT_LINE('DB     : ' || SYS_CONTEXT('USERENV','DB_NAME'));
  DBMS_OUTPUT.PUT_LINE('Time   : ' || TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS'));
  DBMS_OUTPUT.PUT_LINE('===========================================');
END;
/

-- ============================================================
-- 1. SEQUENCES
-- ============================================================
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_sequences WHERE sequence_name = 'CRMS_RELEASE_SEQ';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE 'CREATE SEQUENCE crms_release_seq START WITH 11973 INCREMENT BY 1 NOCACHE NOCYCLE';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_release_seq');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_release_seq'); END IF;
END;
/

DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_sequences WHERE sequence_name = 'CRMS_TASK_SEQ';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE 'CREATE SEQUENCE crms_task_seq START WITH 15933 INCREMENT BY 1 NOCACHE NOCYCLE';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_task_seq');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_task_seq'); END IF;
END;
/

DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_sequences WHERE sequence_name = 'CRMS_RTASK_SEQ';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE 'CREATE SEQUENCE crms_rtask_seq START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_rtask_seq');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_rtask_seq'); END IF;
END;
/

-- ============================================================
-- 2. TABLES (CREATED IN LOGICAL DEPENDENCY ORDER)
-- ============================================================

-- TABLE: 1. crms_users
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_USERS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_users (
        user_id             NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        initials            VARCHAR2(3)    NOT NULL,
        full_name           VARCHAR2(200)  NOT NULL,
        role                VARCHAR2(10)   DEFAULT ''user'' NOT NULL CONSTRAINT chk_user_role CHECK (role IN (''admin'',''user'')),
        password_hash       VARCHAR2(255)  NOT NULL,
        refresh_token_hash  VARCHAR2(255),
        is_active           NUMBER(1)      DEFAULT 1 NOT NULL CONSTRAINT chk_user_active CHECK (is_active IN (0,1)),
        last_login          TIMESTAMP,
        created_at          TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        fnd_user_name       VARCHAR2(100),
        CONSTRAINT uq_user_initials UNIQUE (initials)
      )';
    EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX idx_crms_users_fnd ON crms_users(UPPER(fnd_user_name))';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_users');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_users'); END IF;
END;
/

-- TABLE: 2. crms_assignment_groups
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_ASSIGNMENT_GROUPS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_assignment_groups (
        group_id    NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        group_name  VARCHAR2(200)  NOT NULL,
        description VARCHAR2(500),
        created_at  TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_group_name UNIQUE (group_name)
      )';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_assignment_groups');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_assignment_groups'); END IF;
END;
/

-- TABLE: 3. crms_companies
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_COMPANIES';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_companies (
        company_id   NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        company_name VARCHAR2(200) NOT NULL,
        created_at   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_company_name UNIQUE (company_name)
      )';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_companies');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_companies'); END IF;
END;
/

-- TABLE: 4. crms_services
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_SERVICES';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_services (
        service_id   NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        service_name VARCHAR2(200) NOT NULL,
        created_at   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_service_name UNIQUE (service_name)
      )';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_services');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_services'); END IF;
END;
/

-- TABLE: 5. crms_modules
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_MODULES';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_modules (
        module_id    NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_name  VARCHAR2(200)  NOT NULL,
        description  VARCHAR2(500),
        is_active    NUMBER(1)      DEFAULT 1 NOT NULL CONSTRAINT chk_mod_active CHECK (is_active IN (0,1)),
        created_at   TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_module_name UNIQUE (module_name)
      )';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_modules');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_modules'); END IF;
END;
/

-- TABLE: 6. crms_group_members
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_GROUP_MEMBERS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_group_members (
        group_id   NUMBER NOT NULL CONSTRAINT fk_gm_group REFERENCES crms_assignment_groups(group_id) ON DELETE CASCADE,
        user_id    NUMBER NOT NULL CONSTRAINT fk_gm_user REFERENCES crms_users(user_id) ON DELETE CASCADE,
        joined_at  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT pk_group_members PRIMARY KEY (group_id, user_id)
      )';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_group_members');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_group_members'); END IF;
END;
/

-- TABLE: 7. crms_phase_groups
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_PHASE_GROUPS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_phase_groups (
        phase_group_id NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_id      NUMBER         NOT NULL CONSTRAINT fk_pg_module REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        phase_code     VARCHAR2(20)   NOT NULL CONSTRAINT chk_pg_phase CHECK (phase_code IN (''DRAFT'',''RD'',''FSD'',''DEV'',''TESTING'',''UAT'',''DEPLOYMENT'')),
        group_id       NUMBER         NOT NULL CONSTRAINT fk_pg_group REFERENCES crms_assignment_groups(group_id),
        created_at     TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_pg_module ON crms_phase_groups(module_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_phase_groups');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_phase_groups'); END IF;
END;
/

-- TABLE: 8. crms_phase_templates
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_PHASE_TEMPLATES';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_phase_templates (
        template_id  NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_id    NUMBER         NOT NULL CONSTRAINT fk_pt_module REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        phase_code   VARCHAR2(20)   NOT NULL CONSTRAINT chk_pt_phase CHECK (phase_code IN (''RD'')),
        file_name    VARCHAR2(500)  NOT NULL,
        file_type    VARCHAR2(200),
        file_data    CLOB           NOT NULL,
        uploaded_by  NUMBER         NOT NULL CONSTRAINT fk_pt_user REFERENCES crms_users(user_id),
        created_at   TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_phase_template UNIQUE (module_id, phase_code)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_pt_module ON crms_phase_templates(module_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_phase_templates');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_phase_templates'); END IF;
END;
/

-- TABLE: 9. crms_approval_flows
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_APPROVAL_FLOWS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_approval_flows (
        flow_id          NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_id        NUMBER         NOT NULL CONSTRAINT fk_af_module REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        phase_code       VARCHAR2(20)   NOT NULL CONSTRAINT chk_af_phase CHECK (phase_code IN (''DRAFT'',''RD'',''FSD'',''DEPLOYMENT'')),
        level_order      NUMBER(2)      NOT NULL,
        approver_user_id NUMBER         NOT NULL CONSTRAINT fk_af_user REFERENCES crms_users(user_id),
        auto_approve     NUMBER(1)      DEFAULT 0 NOT NULL CONSTRAINT chk_af_auto CHECK (auto_approve IN (0,1)),
        created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_af_level UNIQUE (module_id, phase_code, level_order)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_af_module ON crms_approval_flows(module_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_approval_flows');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_approval_flows'); END IF;
END;
/

-- TABLE: 10. crms_phase_reviewers
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_PHASE_REVIEWERS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_phase_reviewers (
        reviewer_id  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_id    NUMBER NOT NULL CONSTRAINT fk_pr_module REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        phase_code   VARCHAR2(20) NOT NULL,
        group_id     NUMBER NOT NULL CONSTRAINT fk_pr_group REFERENCES crms_assignment_groups(group_id),
        user_id      NUMBER NOT NULL CONSTRAINT fk_pr_user REFERENCES crms_users(user_id),
        created_at   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
      )';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_phase_reviewers');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_phase_reviewers'); END IF;
END;
/

-- TABLE: 11. crms_phase_process_owners
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_PHASE_PROCESS_OWNERS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_phase_process_owners (
        po_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_id    NUMBER NOT NULL CONSTRAINT fk_po_module REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        phase_code   VARCHAR2(20) NOT NULL,
        group_id     NUMBER NOT NULL CONSTRAINT fk_po_group REFERENCES crms_assignment_groups(group_id),
        user_id      NUMBER NOT NULL CONSTRAINT fk_po_user REFERENCES crms_users(user_id),
        created_at   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_po UNIQUE (module_id, phase_code)
      )';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_phase_process_owners');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_phase_process_owners'); END IF;
END;
/

-- TABLE: 12. crms_releases
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_RELEASES';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_releases (
        release_id          NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_number      VARCHAR2(20)   NOT NULL CONSTRAINT uq_release_number UNIQUE,
        state               VARCHAR2(60)   DEFAULT ''Draft'' NOT NULL CONSTRAINT chk_release_state CHECK (state IN (
                              ''Draft'',
                              ''Draft Awaiting Approval L1'', ''Draft Awaiting Approval L2'', ''Draft Awaiting Approval L3'', ''Draft Awaiting Approval L4'', ''Draft Awaiting Approval L5'',
                              ''RD Phase'',
                              ''RD Awaiting Approval L1'', ''RD Awaiting Approval L2'', ''RD Awaiting Approval L3'', ''RD Awaiting Approval L4'', ''RD Awaiting Approval L5'',
                              ''RD Approval L1'', ''RD Approval L2'', ''RD Approval L3'', ''RD Approval L4'', ''RD Approval L5'',
                              ''RD Approved'',
                              ''FSD Phase'',
                              ''FSD Awaiting Approval L1'', ''FSD Awaiting Approval L2'', ''FSD Awaiting Approval L3'', ''FSD Awaiting Approval L4'', ''FSD Awaiting Approval L5'',
                              ''FSD Approval L1'', ''FSD Approval L2'', ''FSD Approval L3'', ''FSD Approval L4'', ''FSD Approval L5'',
                              ''Development Phase'',
                              ''Testing Phase'',
                              ''Testing/QA'',
                              ''UAT Phase'',
                              ''UAT'',
                              ''Deployment Phase'',
                              ''Deployment Approval L1'', ''Deployment Approval L2'', ''Deployment Approval L3'', ''Deployment Approval L4'', ''Deployment Approval L5'',
                              ''Deployment Awaiting Approval L1'', ''Deployment Awaiting Approval L2'', ''Deployment Awaiting Approval L3'', ''Deployment Awaiting Approval L4'', ''Deployment Awaiting Approval L5'',
                              ''Observation Phase'',
                              ''On Hold'', ''Closed'', ''Cancelled''
                            )),
        priority            VARCHAR2(1)    NOT NULL CONSTRAINT chk_release_priority CHECK (priority IN (''1'',''2'',''3'',''4'')),
        title               VARCHAR2(200)  NOT NULL,
        summary             CLOB,
        company             VARCHAR2(200),
        service             VARCHAR2(200),
        planned_start_date  DATE,
        target_end_date     DATE,
        requested_by        NUMBER         NOT NULL CONSTRAINT fk_rel_requested_by REFERENCES crms_users(user_id),
        assignment_group_id NUMBER         CONSTRAINT fk_rel_ag REFERENCES crms_assignment_groups(group_id),
        assigned_to_user_id NUMBER         CONSTRAINT fk_rel_assigned_to REFERENCES crms_users(user_id),
        is_deleted          NUMBER(1)      DEFAULT 0 NOT NULL CONSTRAINT chk_release_deleted CHECK (is_deleted IN (0,1)),
        created_at          TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        updated_at          TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        module_id           NUMBER         CONSTRAINT fk_rel_module REFERENCES crms_modules(module_id) ON DELETE SET NULL,
        current_approval_level NUMBER      DEFAULT 0 NOT NULL,
        reason_of_change    VARCHAR2(1000),
        business_benefits_process VARCHAR2(1000),
        business_benefits_qualitative VARCHAR2(1000),
        cost_saving         VARCHAR2(1000),
        manpower_saving     VARCHAR2(1000),
        cemli               VARCHAR2(200),
        smartsheet_id       VARCHAR2(200),
        process_name        VARCHAR2(500),
        cr_owner_user_id    NUMBER         CONSTRAINT fk_rel_cr_owner REFERENCES crms_users(user_id),
        CONSTRAINT chk_release_dates CHECK (target_end_date IS NULL OR target_end_date >= planned_start_date)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rel_state   ON crms_releases(state)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rel_reqby   ON crms_releases(requested_by)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rel_ag      ON crms_releases(assignment_group_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rel_priority ON crms_releases(priority)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rel_startdt  ON crms_releases(planned_start_date)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rel_deleted  ON crms_releases(is_deleted)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rel_cr_owner ON crms_releases(cr_owner_user_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_releases');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_releases'); END IF;
END;
/

-- TABLE: 13. crms_release_history
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_RELEASE_HISTORY';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_release_history (
        history_id   NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_id   NUMBER        NOT NULL CONSTRAINT fk_hist_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        action       VARCHAR2(50)  NOT NULL,
        from_state   VARCHAR2(60),
        to_state     VARCHAR2(60)  NOT NULL,
        changed_by   NUMBER        NOT NULL CONSTRAINT fk_hist_user REFERENCES crms_users(user_id),
        changed_at   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_hist_release ON crms_release_history(release_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_release_history');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_release_history'); END IF;
END;
/

-- TABLE: 14. crms_tasks (Legacy Phase Tasks)
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_TASKS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_tasks (
        task_id             NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        task_number         VARCHAR2(20)  NOT NULL CONSTRAINT uq_task_number UNIQUE,
        release_id          NUMBER        NOT NULL CONSTRAINT fk_task_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        phase               VARCHAR2(10)  NOT NULL CONSTRAINT chk_task_phase CHECK (phase IN (''BRD'',''FSD'',''Dev'',''Testing'',''UAT'')),
        task_type           VARCHAR2(30)  NOT NULL,
        state               VARCHAR2(10)  DEFAULT ''Open'' NOT NULL CONSTRAINT chk_task_state CHECK (state IN (''Open'',''Closed'')),
        short_description   VARCHAR2(500) NOT NULL,
        assignment_group_id NUMBER         CONSTRAINT fk_task_ag REFERENCES crms_assignment_groups(group_id),
        assigned_to_user_id NUMBER         CONSTRAINT fk_task_assigned REFERENCES crms_users(user_id),
        created_by          NUMBER        NOT NULL CONSTRAINT fk_task_createdby REFERENCES crms_users(user_id),
        created_at          TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
        updated_at          TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_task_release  ON crms_tasks(release_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_task_assigned ON crms_tasks(assigned_to_user_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_task_state     ON crms_tasks(state)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_tasks');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_tasks'); END IF;
END;
/

-- TABLE: 15. crms_comments
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_COMMENTS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_comments (
        comment_id    NUMBER   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_id    NUMBER   NOT NULL CONSTRAINT fk_comment_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        comment_text  CLOB     NOT NULL,
        created_by    NUMBER   NOT NULL CONSTRAINT fk_comment_user REFERENCES crms_users(user_id),
        created_at    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_comment_release ON crms_comments(release_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_comments');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_comments'); END IF;
END;
/

-- TABLE: 16. crms_notifications
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_NOTIFICATIONS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_notifications (
        notification_id  NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        user_id          NUMBER         NOT NULL CONSTRAINT fk_notif_user REFERENCES crms_users(user_id) ON DELETE CASCADE,
        title            VARCHAR2(100)  NOT NULL,
        message          VARCHAR2(500)  NOT NULL,
        is_read          NUMBER(1)      DEFAULT 0 NOT NULL CONSTRAINT chk_notif_read CHECK (is_read IN (0,1)),
        release_id       NUMBER         CONSTRAINT fk_notif_release REFERENCES crms_releases(release_id) ON DELETE SET NULL,
        created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_notif_user   ON crms_notifications(user_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_notif_unread  ON crms_notifications(user_id, is_read)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_notifications');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_notifications'); END IF;
END;
/

-- TABLE: 17. crms_audit
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_AUDIT';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_audit (
        audit_id      NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        action        VARCHAR2(50)   NOT NULL,
        performed_by  NUMBER         NOT NULL CONSTRAINT fk_audit_user REFERENCES crms_users(user_id),
        cr_number     VARCHAR2(20)   DEFAULT ''--'' NOT NULL,
        details       VARCHAR2(1000),
        created_at    TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_audit_user    ON crms_audit(performed_by)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_audit_action   ON crms_audit(action)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_audit_crnum    ON crms_audit(cr_number)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_audit_createdat ON crms_audit(created_at DESC)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_audit');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_audit'); END IF;
END;
/

-- TABLE: 18. crms_attachments
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_ATTACHMENTS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_attachments (
        attachment_id   NUMBER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_id      NUMBER          NOT NULL CONSTRAINT fk_att_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        file_name       VARCHAR2(500)   NOT NULL,
        file_type       VARCHAR2(200),
        file_size       NUMBER,
        file_data       CLOB            NOT NULL,
        uploaded_by     NUMBER          NOT NULL CONSTRAINT fk_att_user REFERENCES crms_users(user_id),
        created_at      TIMESTAMP       DEFAULT SYSTIMESTAMP NOT NULL,
        phase_code      VARCHAR2(20),
        task_id         NUMBER
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_att_release ON crms_attachments(release_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_att_user    ON crms_attachments(uploaded_by)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_attachments');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_attachments'); END IF;
END;
/

-- TABLE: 19. crms_release_approvals
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_RELEASE_APPROVALS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_release_approvals (
        approval_id      NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_id       NUMBER         NOT NULL CONSTRAINT fk_ra_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        module_id        NUMBER         NOT NULL,
        phase_code       VARCHAR2(20)   NOT NULL,
        level_order      NUMBER(2)      NOT NULL,
        approver_user_id NUMBER         NOT NULL CONSTRAINT fk_ra_approver REFERENCES crms_users(user_id),
        status           VARCHAR2(10)   DEFAULT ''Pending'' NOT NULL CONSTRAINT chk_ra_status CHECK (status IN (''Pending'',''Approved'',''Rejected'',''Skipped'')),
        comments         VARCHAR2(2000),
        actioned_at      TIMESTAMP,
        created_at       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_ra_release  ON crms_release_approvals(release_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_ra_approver ON crms_release_approvals(approver_user_id,status)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_release_approvals');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_release_approvals'); END IF;
END;
/

-- TABLE: 20. crms_release_tasks (RTSK Sub-Tasks per Phase)
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_RELEASE_TASKS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_release_tasks (
        task_id              NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        task_number          VARCHAR2(20)   NOT NULL CONSTRAINT uq_rt_number UNIQUE,
        release_id           NUMBER         NOT NULL CONSTRAINT fk_rt_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        phase_code           VARCHAR2(20)   NOT NULL CONSTRAINT chk_rt_phase CHECK (phase_code IN (''RD'',''FSD'',''DEV'',''TESTING'',''UAT'',''DEPLOYMENT'')),
        assigned_to          NUMBER         NOT NULL CONSTRAINT fk_rt_assignee REFERENCES crms_users(user_id),
        state                VARCHAR2(10)   DEFAULT ''Open'' NOT NULL CONSTRAINT chk_rt_state CHECK (state IN (''Open'',''Closed'')),
        template_downloaded  NUMBER(1)      DEFAULT 0,
        upload_attachment_id NUMBER,
        short_description    VARCHAR2(500),
        closed_by            NUMBER         CONSTRAINT fk_rt_closedby REFERENCES crms_users(user_id),
        closed_at            TIMESTAMP,
        created_at           TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        cemli                VARCHAR2(200),
        smartsheet_id        VARCHAR2(200),
        process_name         VARCHAR2(500),
        delay_reason         VARCHAR2(2000)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rt_release  ON crms_release_tasks(release_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rt_assignee ON crms_release_tasks(assigned_to)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rt_phase    ON crms_release_tasks(release_id,phase_code)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_release_tasks');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_release_tasks'); END IF;
END;
/

-- TABLE: 21. crms_release_phase_groups (CR-Level Overrides)
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_RELEASE_PHASE_GROUPS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_release_phase_groups (
        rpg_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_id   NUMBER NOT NULL CONSTRAINT fk_rpg_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        phase_code   VARCHAR2(20) NOT NULL,
        group_id     NUMBER NOT NULL CONSTRAINT fk_rpg_group REFERENCES crms_assignment_groups(group_id),
        created_at   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_rpg UNIQUE (release_id, phase_code)
      )';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_release_phase_groups');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_release_phase_groups'); END IF;
END;
/

-- TABLE: 22. crms_review_requests
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_REVIEW_REQUESTS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_review_requests (
        review_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_id      NUMBER NOT NULL CONSTRAINT fk_rr_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        phase_code      VARCHAR2(20) NOT NULL,
        sent_by         NUMBER NOT NULL CONSTRAINT fk_rr_sent_by REFERENCES crms_users(user_id),
        reviewer_id     NUMBER NOT NULL CONSTRAINT fk_rr_reviewer REFERENCES crms_users(user_id),
        passed_to       NUMBER         CONSTRAINT fk_rr_passed REFERENCES crms_users(user_id),
        status          VARCHAR2(20) DEFAULT ''Pending'' NOT NULL,
        notes           VARCHAR2(1000),
        created_at      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        updated_at      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rr_reviewer ON crms_review_requests(reviewer_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rr_release  ON crms_review_requests(release_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_review_requests');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_review_requests'); END IF;
END;
/

-- TABLE: 23. crms_task_list
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_TASK_LIST';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_task_list (
        task_list_id     NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        reported_on      VARCHAR2(50),
        requester        VARCHAR2(200),
        cemli            VARCHAR2(200),
        service_now_id   VARCHAR2(200),
        ticket_no        VARCHAR2(200),
        smart_sheet      VARCHAR2(500),
        project          VARCHAR2(200),
        module           VARCHAR2(200),
        process          VARCHAR2(200),
        task_title       VARCHAR2(1000),
        owner            VARCHAR2(200),
        status           VARCHAR2(50)  DEFAULT ''NOT STARTED'' CONSTRAINT chk_tl_status CHECK (status IN (''OPEN'',''HOLD'',''DROP'',''COMPLETE'',''NOT STARTED'')),
        stage            VARCHAR2(100),
        pending_with     VARCHAR2(200),
        cr_task_id       VARCHAR2(200),
        cr_number        VARCHAR2(50),
        auto_populated   NUMBER(1)     DEFAULT 0 CONSTRAINT chk_tl_auto CHECK (auto_populated IN (0,1)),
        created_by       NUMBER        NOT NULL CONSTRAINT fk_tl_created_by REFERENCES crms_users(user_id),
        created_at       TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
        updated_at       TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
        is_deleted       NUMBER(1)     DEFAULT 0 CONSTRAINT chk_tl_deleted CHECK (is_deleted IN (0,1)),
        delay_reason     VARCHAR2(1000),
        comments         VARCHAR2(2000),
        tracker_comments VARCHAR2(2000),
        rd_approval_dt   VARCHAR2(50),
        md50_st          VARCHAR2(50),
        md50_end         VARCHAR2(50),
        md50_app_by      VARCHAR2(200),
        md50_app_on      VARCHAR2(50),
        dev_st           VARCHAR2(50),
        dev_end          VARCHAR2(50),
        tft_st           VARCHAR2(50),
        tft_end          VARCHAR2(50),
        uat_closed_on    VARCHAR2(50),
        approved1_on     VARCHAR2(50),
        approved2_on     VARCHAR2(50),
        approved3_on     VARCHAR2(50),
        deployed_samil   VARCHAR2(50),
        deployed_mswil   VARCHAR2(50)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_tl_created_by  ON crms_task_list(created_by)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_tl_status      ON crms_task_list(status)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_tl_cr_number   ON crms_task_list(cr_number)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_tl_cr_task_id  ON crms_task_list(cr_task_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_task_list');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_task_list'); END IF;
END;
/

-- TABLE: 24. crms_task_list_editors
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_TASK_LIST_EDITORS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_task_list_editors (
        editor_id  NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        user_id    NUMBER         NOT NULL CONSTRAINT fk_tl_editor_user REFERENCES crms_users(user_id) ON DELETE CASCADE,
        added_by   NUMBER         NOT NULL CONSTRAINT fk_tl_editor_addedby REFERENCES crms_users(user_id),
        added_at   TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_tl_editor UNIQUE (user_id)
      )';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_task_list_editors');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_task_list_editors'); END IF;
END;
/

-- TABLE: 25. user_sessions
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'USER_SESSIONS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE user_sessions (
        session_id          NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        user_id             NUMBER         NOT NULL CONSTRAINT fk_session_user REFERENCES crms_users(user_id),
        refresh_token_hash  VARCHAR2(255)  NOT NULL,
        device_id           VARCHAR2(64),
        device_name         VARCHAR2(200),
        browser             VARCHAR2(100),
        operating_system    VARCHAR2(100),
        ip_address          VARCHAR2(45),
        user_agent          VARCHAR2(500),
        status              VARCHAR2(10)   DEFAULT ''ACTIVE'' NOT NULL CONSTRAINT chk_session_status CHECK (status IN (''ACTIVE'',''REVOKED'',''EXPIRED'')),
        created_at          TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        last_activity       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        session_expires_at  TIMESTAMP      NOT NULL,
        revoked_at          TIMESTAMP
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_sessions_user_id ON user_sessions(user_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_sessions_hash ON user_sessions(refresh_token_hash)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_sessions_status ON user_sessions(user_id, status)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_sessions_expires ON user_sessions(session_expires_at)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : user_sessions');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : user_sessions'); END IF;
END;
/

-- TABLE: 26. crms_sso_tokens
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_SSO_TOKENS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_sso_tokens (
        token_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        token       VARCHAR2(64)  NOT NULL UNIQUE,
        fnd_user_id NUMBER        NOT NULL,
        crms_user_id NUMBER       NOT NULL CONSTRAINT fk_sso_crms_user REFERENCES crms_users(user_id),
        created_at  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        expires_at  TIMESTAMP NOT NULL,
        used        NUMBER(1) DEFAULT 0 NOT NULL,
        used_at     TIMESTAMP
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_sso_token  ON crms_sso_tokens(token)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_sso_expires ON crms_sso_tokens(expires_at)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_sso_tokens');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_sso_tokens'); END IF;
END;
/

-- TABLE: 27. crms_module_users
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_MODULE_USERS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_module_users (
        module_user_id  NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        module_id       NUMBER         NOT NULL CONSTRAINT fk_mu_module REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        user_id         NUMBER         NOT NULL CONSTRAINT fk_mu_user REFERENCES crms_users(user_id) ON DELETE CASCADE,
        is_requester    NUMBER(1)      DEFAULT 1 NOT NULL CONSTRAINT chk_mu_req CHECK (is_requester IN (0,1)),
        is_approver     NUMBER(1)      DEFAULT 0 NOT NULL CONSTRAINT chk_mu_app CHECK (is_approver IN (0,1)),
        created_at      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_module_user UNIQUE (module_id, user_id)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_mu_user   ON crms_module_users(user_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_mu_module ON crms_module_users(module_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_module_users');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_module_users'); END IF;
END;
/

-- TABLE: 28. crms_approval_flow_approvers
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_APPROVAL_FLOW_APPROVERS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_approval_flow_approvers (
        id               NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        flow_id          NUMBER         NOT NULL CONSTRAINT fk_afa_flow REFERENCES crms_approval_flows(flow_id) ON DELETE CASCADE,
        approver_user_id NUMBER         NOT NULL CONSTRAINT fk_afa_user REFERENCES crms_users(user_id),
        CONSTRAINT uq_afa_flow_user UNIQUE (flow_id, approver_user_id)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_afa_flow ON crms_approval_flow_approvers(flow_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_afa_user ON crms_approval_flow_approvers(approver_user_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_approval_flow_approvers');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_approval_flow_approvers'); END IF;
END;
/

-- TABLE: 29. crms_company_service_map
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_COMPANY_SERVICE_MAP';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_company_service_map (
        map_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        company_id    NUMBER NOT NULL CONSTRAINT fk_csm_company REFERENCES crms_companies(company_id) ON DELETE CASCADE,
        service_id    NUMBER NOT NULL CONSTRAINT fk_csm_service REFERENCES crms_services(service_id) ON DELETE CASCADE,
        created_at    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_company_service UNIQUE (company_id, service_id)
      )';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_company_service_map');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_company_service_map'); END IF;
END;
/

-- TABLE: 30. crms_company_group_phase_map
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_COMPANY_GROUP_PHASE_MAP';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_company_group_phase_map (
        phase_map_id  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        company_id    NUMBER NOT NULL CONSTRAINT fk_cgpm_company REFERENCES crms_companies(company_id) ON DELETE CASCADE,
        service_id    NUMBER NOT NULL CONSTRAINT fk_cgpm_service REFERENCES crms_services(service_id) ON DELETE CASCADE,
        group_id      NUMBER NOT NULL CONSTRAINT fk_cgpm_group REFERENCES crms_assignment_groups(group_id) ON DELETE CASCADE,
        phase_code    VARCHAR2(20) NOT NULL CONSTRAINT chk_cgpm_phase CHECK (phase_code IN (''ALL'',''RD'',''FSD'',''DEV'',''TESTING'',''UAT'',''DEPLOYMENT'')),
        created_at    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_company_service_group_phase UNIQUE (company_id, service_id, group_id, phase_code)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_cgpm_co_svc ON crms_company_group_phase_map(company_id, service_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_company_group_phase_map');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_company_group_phase_map'); END IF;
END;
/

-- TABLE: 31. crms_approval_groups
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_APPROVAL_GROUPS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_approval_groups (
        ag_map_id    NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        company_name VARCHAR2(200),
        service_name VARCHAR2(200),
        module_id    NUMBER         CONSTRAINT fk_apgrp_mod REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        group_id     NUMBER         NOT NULL CONSTRAINT fk_apgrp_grp REFERENCES crms_assignment_groups(group_id) ON DELETE CASCADE,
        phase_code   VARCHAR2(20)   DEFAULT ''RD'' NOT NULL,
        created_at   TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        level_order  NUMBER         DEFAULT 1 NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_apgrp_company ON crms_approval_groups(company_name)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_apgrp_module  ON crms_approval_groups(module_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_apgrp_level   ON crms_approval_groups(phase_code,level_order)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_approval_groups');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_approval_groups'); END IF;
END;
/

-- TABLE: 32. crms_release_reviews
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_RELEASE_REVIEWS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_release_reviews (
        review_id           NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_id          NUMBER         NOT NULL CONSTRAINT fk_rr_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        module_id           NUMBER         NOT NULL CONSTRAINT fk_rr_module REFERENCES crms_modules(module_id),
        phase_code          VARCHAR2(20)   NOT NULL,
        reviewer_user_id    NUMBER         NOT NULL CONSTRAINT fk_rr_reviewer REFERENCES crms_users(user_id),
        created_by_user_id  NUMBER         NOT NULL CONSTRAINT fk_rr_created_by REFERENCES crms_users(user_id),
        parent_review_id    NUMBER         CONSTRAINT fk_rr_parent REFERENCES crms_release_reviews(review_id),
        status              VARCHAR2(20)   DEFAULT ''Pending'' NOT NULL CONSTRAINT chk_rr_status CHECK (status IN (''Pending'',''Referred'')),
        actioned_at         TIMESTAMP,
        created_at          TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rr_reviewer ON crms_release_reviews(reviewer_user_id, status)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rr_release  ON crms_release_reviews(release_id, phase_code)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_release_reviews');
  ELSE DBMS_OUTPUT.PUT_LINE('  EXISTS  : crms_release_reviews'); END IF;
END;
/

-- ============================================================
-- 3. TRIGGERS
-- ============================================================
CREATE OR REPLACE TRIGGER trg_releases_updated_at
  BEFORE UPDATE ON crms_releases
  FOR EACH ROW
BEGIN
  :NEW.updated_at := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER trg_tasks_updated_at
  BEFORE UPDATE ON crms_tasks
  FOR EACH ROW
BEGIN
  :NEW.updated_at := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER trg_task_list_updated_at
  BEFORE UPDATE ON crms_task_list
  FOR EACH ROW
BEGIN
  :NEW.updated_at := SYSTIMESTAMP;
END;
/

-- ============================================================
-- 4. VIEWS
-- ============================================================
CREATE OR REPLACE VIEW vw_releases_summary AS
SELECT
  r.release_id,
  r.release_number,
  r.state,
  r.priority,
  CASE r.priority
    WHEN '1' THEN '1 – Critical' WHEN '2' THEN '2 – High'
    WHEN '3' THEN '3 – Moderate' WHEN '4' THEN '4 – Low'
    ELSE r.priority
  END AS priority_label,
  r.title,
  r.company,
  r.service,
  r.planned_start_date,
  r.target_end_date,
  TRUNC(SYSDATE - r.planned_start_date)          AS sla_age_days,
  u_req.full_name                                 AS requested_by,
  u_ass.full_name                                 AS assigned_to,
  ag.group_name                                   AS assignment_group,
  r.created_at,
  r.updated_at,
  (SELECT COUNT(*) FROM crms_release_tasks t WHERE t.release_id = r.release_id)       AS task_count,
  (SELECT COUNT(*) FROM crms_release_tasks t WHERE t.release_id = r.release_id AND t.state = 'Open')  AS open_task_count,
  (SELECT COUNT(*) FROM crms_comments c WHERE c.release_id = r.release_id)    AS comment_count
FROM  crms_releases r
JOIN  crms_users u_req ON u_req.user_id = r.requested_by
LEFT  JOIN crms_users u_ass ON u_ass.user_id = r.assigned_to_user_id
LEFT  JOIN crms_assignment_groups ag ON ag.group_id = r.assignment_group_id
WHERE r.is_deleted = 0;
/

CREATE OR REPLACE VIEW vw_analytics_by_group AS
SELECT
  ag.group_id,
  ag.group_name,
  COUNT(r.release_id)                                           AS total_releases,
  COUNT(CASE WHEN r.state NOT IN ('Closed','Cancelled') THEN 1 END) AS open_releases,
  COUNT(CASE WHEN r.state = 'Closed'    THEN 1 END)            AS closed_releases,
  COUNT(CASE WHEN r.state = 'Cancelled' THEN 1 END)            AS cancelled_releases,
  COUNT(CASE WHEN r.priority = '1' AND r.state NOT IN ('Closed','Cancelled') THEN 1 END) AS critical_open
FROM crms_assignment_groups ag
LEFT JOIN crms_releases r ON r.assignment_group_id = ag.group_id AND r.is_deleted = 0
GROUP BY ag.group_id, ag.group_name;
/

CREATE OR REPLACE VIEW vw_company_group_phase AS
SELECT
  m.phase_map_id,
  m.company_id,
  c.company_name,
  m.service_id,
  s.service_name,
  m.group_id,
  g.group_name,
  m.phase_code
FROM crms_company_group_phase_map m
JOIN crms_companies         c ON c.company_id  = m.company_id
JOIN crms_services          s ON s.service_id  = m.service_id
JOIN crms_assignment_groups g ON g.group_id    = m.group_id;
/

-- ============================================================
-- 5. PROCEDURES
-- ============================================================
CREATE OR REPLACE PROCEDURE crms_expire_sessions AS
  v_count NUMBER;
BEGIN
  UPDATE user_sessions
     SET status = 'EXPIRED'
   WHERE status = 'ACTIVE'
     AND session_expires_at < SYSTIMESTAMP;
  v_count := SQL%ROWCOUNT;
  COMMIT;
  IF v_count > 0 THEN
    DBMS_OUTPUT.PUT_LINE('  EXPIRED : ' || v_count || ' stale session(s)');
  END IF;
END crms_expire_sessions;
/

CREATE OR REPLACE PROCEDURE crms_purge_old_sessions(
  p_retention_days IN NUMBER DEFAULT 90
) AS
  v_count NUMBER;
BEGIN
  UPDATE user_sessions
     SET status = 'EXPIRED'
   WHERE status = 'ACTIVE'
     AND session_expires_at < SYSTIMESTAMP;
  COMMIT;

  DELETE FROM user_sessions
   WHERE status IN ('REVOKED', 'EXPIRED')
     AND NVL(revoked_at, session_expires_at) < SYSTIMESTAMP - p_retention_days;
  v_count := SQL%ROWCOUNT;
  COMMIT;
  IF v_count > 0 THEN
    DBMS_OUTPUT.PUT_LINE('  PURGED  : ' || v_count || ' old session(s) deleted');
  END IF;
END crms_purge_old_sessions;
/

-- ============================================================
-- 6. SCHEDULER PURGE JOB
-- ============================================================
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'CRMS_PURGE_SESSIONS',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN crms_expire_sessions; crms_purge_old_sessions(90); END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY;BYHOUR=2;BYMINUTE=0;BYSECOND=0',
    enabled         => TRUE,
    comments        => 'CRMS: Expire stale sessions and purge old revoked/expired sessions (90 day retention)'
  );
  DBMS_OUTPUT.PUT_LINE('  JOB     : CRMS_PURGE_SESSIONS created (daily at 2 AM)');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -27477 THEN
      DBMS_OUTPUT.PUT_LINE('  JOB     : CRMS_PURGE_SESSIONS already exists');
    ELSE
      DBMS_OUTPUT.PUT_LINE('  JOB     : Failed to create scheduler job - ' || SQLERRM);
    END IF;
END;
/

COMMIT;
DBMS_OUTPUT.PUT_LINE('===========================================');
DBMS_OUTPUT.PUT_LINE('CRMS Master DDL Migration Completed Successfully!');
DBMS_OUTPUT.PUT_LINE('===========================================');
