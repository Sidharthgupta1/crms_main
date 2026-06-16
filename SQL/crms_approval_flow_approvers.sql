-- ============================================================
-- CRMS APPROVAL FLOW APPROVERS
-- Multiple supervisors per approval level (any-one-can-approve)
-- Backward compatible: keeps approver_user_id on crms_approval_flows
-- ============================================================

SET ECHO OFF
SET SERVEROUTPUT ON
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE

BEGIN
  DBMS_OUTPUT.PUT_LINE('===========================================');
  DBMS_OUTPUT.PUT_LINE('CRMS Approval Flow Approvers - Starting');
  DBMS_OUTPUT.PUT_LINE('Time : ' || TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS'));
  DBMS_OUTPUT.PUT_LINE('===========================================');
END;
/

-- ============================================================
-- Step 1: Create mapping table
-- ============================================================
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_APPROVAL_FLOW_APPROVERS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_approval_flow_approvers (
        id               NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        flow_id          NUMBER         NOT NULL
            CONSTRAINT fk_afa_flow REFERENCES crms_approval_flows(flow_id) ON DELETE CASCADE,
        approver_user_id NUMBER         NOT NULL
            CONSTRAINT fk_afa_user REFERENCES crms_users(user_id),
        CONSTRAINT uq_afa_flow_user UNIQUE (flow_id, approver_user_id)
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_afa_flow ON crms_approval_flow_approvers(flow_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_afa_user ON crms_approval_flow_approvers(approver_user_id)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_approval_flow_approvers');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : crms_approval_flow_approvers (exists)');
  END IF;
END;
/

-- ============================================================
-- Step 2: Migrate existing approvers into mapping table
-- ============================================================
DECLARE
  v_cnt NUMBER;
BEGIN
  INSERT INTO crms_approval_flow_approvers (flow_id, approver_user_id)
  SELECT af.flow_id, af.approver_user_id
  FROM crms_approval_flows af
  WHERE af.approver_user_id IS NOT NULL
    AND af.approver_user_id > 0
    AND NOT EXISTS (
      SELECT 1 FROM crms_approval_flow_approvers afa
      WHERE afa.flow_id = af.flow_id AND afa.approver_user_id = af.approver_user_id
    );
  v_cnt := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('  MIGRATED: ' || v_cnt || ' approver rows into mapping table');
END;
/

-- ============================================================
-- Step 3: Add Skipped status to crms_release_approvals
-- ============================================================
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_constraints
   WHERE table_name = 'CRMS_RELEASE_APPROVALS' AND constraint_name = 'CHK_RA_STATUS';
  IF v_exists > 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_approvals DROP CONSTRAINT chk_ra_status';
    DBMS_OUTPUT.PUT_LINE('  DROPPED : chk_ra_status');
  END IF;
END;
/

DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_constraints
   WHERE table_name = 'CRMS_RELEASE_APPROVALS' AND constraint_name = 'CHK_RA_STATUS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE q'[
      ALTER TABLE crms_release_approvals ADD CONSTRAINT chk_ra_status
        CHECK (status IN ('Pending','Approved','Rejected','Skipped'))]';
    DBMS_OUTPUT.PUT_LINE('  CREATED : chk_ra_status (with Skipped)');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : chk_ra_status already exists');
  END IF;
END;
/

COMMIT;

BEGIN
  DBMS_OUTPUT.PUT_LINE('===========================================');
  DBMS_OUTPUT.PUT_LINE('CRMS Approval Flow Approvers - Done');
  DBMS_OUTPUT.PUT_LINE('===========================================');
END;
/
