-- ============================================================
-- CRMS ATTACHMENTS DDL
-- Run as: APPS user on ebs_MSWILDEV
-- Adds: crms_attachments table + updates state constraint
-- ============================================================

SET ECHO OFF
SET SERVEROUTPUT ON
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE

BEGIN
  DBMS_OUTPUT.PUT_LINE('===========================================');
  DBMS_OUTPUT.PUT_LINE('CRMS Attachments DDL - Starting');
  DBMS_OUTPUT.PUT_LINE('Time : ' || TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS'));
  DBMS_OUTPUT.PUT_LINE('===========================================');
END;
/

-- ============================================================
-- Step 1: Create crms_attachments table
-- Stores file attachments per release
-- file_data: base64-encoded file content (Phase 1 — no file server)
-- ============================================================
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_ATTACHMENTS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_attachments (
        attachment_id   NUMBER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_id      NUMBER          NOT NULL
            CONSTRAINT fk_att_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        file_name       VARCHAR2(500)   NOT NULL,
        file_type       VARCHAR2(200),
        file_size       NUMBER,
        file_data       CLOB            NOT NULL,
        uploaded_by     NUMBER          NOT NULL
            CONSTRAINT fk_att_user REFERENCES crms_users(user_id),
        created_at      TIMESTAMP       DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_att_release ON crms_attachments(release_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_att_user    ON crms_attachments(uploaded_by)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_attachments');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : crms_attachments (exists)');
  END IF;
END;
/

-- ============================================================
-- Step 2: Update state constraint to include RD Approved
-- ============================================================
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_constraints
   WHERE table_name = 'CRMS_RELEASES' AND constraint_name = 'CHK_RELEASE_STATE';
  IF v_exists > 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases DROP CONSTRAINT chk_release_state';
    DBMS_OUTPUT.PUT_LINE('  DROPPED : old chk_release_state');
  END IF;
END;
/

DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_constraints
   WHERE table_name = 'CRMS_RELEASES' AND constraint_name = 'CHK_RELEASE_STATE';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE q'[ALTER TABLE crms_releases ADD CONSTRAINT chk_release_state
      CHECK (state IN (
        'Draft',
        'RD Phase',
        'RD Awaiting Approval L1','RD Awaiting Approval L2','RD Awaiting Approval L3',
        'RD Awaiting Approval L4','RD Awaiting Approval L5',
        'RD Approved',
        'FSD Phase',
        'FSD Awaiting Approval L1','FSD Awaiting Approval L2','FSD Awaiting Approval L3',
        'FSD Awaiting Approval L4','FSD Awaiting Approval L5',
        'Development Phase','On Hold','Testing/QA','UAT','Deployment','Closed','Cancelled'
      ))]';
    DBMS_OUTPUT.PUT_LINE('  CREATED : chk_release_state (with RD Approved)');
  END IF;
END;
/

COMMIT;

-- ============================================================
-- VERIFICATION
-- ============================================================
DECLARE
  v_cnt NUMBER;
BEGIN
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM crms_attachments' INTO v_cnt;
  DBMS_OUTPUT.PUT_LINE('  crms_attachments : ' || v_cnt || ' rows');
  DBMS_OUTPUT.PUT_LINE('  State constraint updated with RD Approved state');
  DBMS_OUTPUT.PUT_LINE('===========================================');
  DBMS_OUTPUT.PUT_LINE('Attachments DDL complete.');
  DBMS_OUTPUT.PUT_LINE('===========================================');
END;
/
