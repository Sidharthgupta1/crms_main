-- ============================================================
-- CRMS: Add phase_code to crms_approval_flows
-- Run this in SQL Developer as APPS user
-- Migrates flow_type -> phase_code so the Node.js code works
-- ============================================================

SET ECHO OFF
SET SERVEROUTPUT ON
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE

BEGIN
  DBMS_OUTPUT.PUT_LINE('===========================================');
  DBMS_OUTPUT.PUT_LINE('CRMS Approval Flow - Add phase_code');
  DBMS_OUTPUT.PUT_LINE('Time : ' || TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS'));
  DBMS_OUTPUT.PUT_LINE('===========================================');
END;
/

-- Step 1: Add phase_code column if missing
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists
    FROM user_tab_columns
   WHERE table_name = 'CRMS_APPROVAL_FLOWS' AND column_name = 'PHASE_CODE';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_approval_flows ADD (phase_code VARCHAR2(20))';
    DBMS_OUTPUT.PUT_LINE('  ADDED   : phase_code column');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : phase_code already exists');
  END IF;
END;
/

-- Step 2: Populate phase_code from flow_type for existing rows
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists
    FROM user_tab_columns
   WHERE table_name = 'CRMS_APPROVAL_FLOWS' AND column_name = 'FLOW_TYPE';
  IF v_exists > 0 THEN
    EXECUTE IMMEDIATE 'UPDATE crms_approval_flows SET phase_code = flow_type WHERE phase_code IS NULL AND flow_type IS NOT NULL';
    DBMS_OUTPUT.PUT_LINE('  MIGRATED: flow_type -> phase_code');
  ELSE
    -- No flow_type column means original schema; default to RD
    EXECUTE IMMEDIATE 'UPDATE crms_approval_flows SET phase_code = ''RD'' WHERE phase_code IS NULL';
    DBMS_OUTPUT.PUT_LINE('  MIGRATED: defaulted phase_code to RD');
  END IF;
END;
/

-- Step 3: Make phase_code NOT NULL
DECLARE
  v_nullable VARCHAR2(1);
BEGIN
  SELECT nullable INTO v_nullable
    FROM user_tab_columns
   WHERE table_name = 'CRMS_APPROVAL_FLOWS' AND column_name = 'PHASE_CODE';
  IF v_nullable = 'Y' THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_approval_flows MODIFY (phase_code VARCHAR2(20) DEFAULT ''RD'' NOT NULL)';
    DBMS_OUTPUT.PUT_LINE('  ALTERED : phase_code set to NOT NULL');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : phase_code already NOT NULL');
  END IF;
EXCEPTION WHEN NO_DATA_FOUND THEN
  DBMS_OUTPUT.PUT_LINE('  ERROR   : phase_code column not found');
END;
/

-- Step 4: Drop old unique constraint uq_flow_level (module_id, level_order)
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_constraints
   WHERE table_name = 'CRMS_APPROVAL_FLOWS' AND constraint_name = 'UQ_FLOW_LEVEL';
  IF v_exists > 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_approval_flows DROP CONSTRAINT uq_flow_level';
    DBMS_OUTPUT.PUT_LINE('  DROPPED : uq_flow_level');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : uq_flow_level not found');
  END IF;
END;
/

-- Step 5: Drop old V2 unique constraint uq_flow_type_level (module_id, flow_type, level_order)
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_constraints
   WHERE table_name = 'CRMS_APPROVAL_FLOWS' AND constraint_name = 'UQ_FLOW_TYPE_LEVEL';
  IF v_exists > 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_approval_flows DROP CONSTRAINT uq_flow_type_level';
    DBMS_OUTPUT.PUT_LINE('  DROPPED : uq_flow_type_level');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : uq_flow_type_level not found');
  END IF;
END;
/

-- Step 6: Create new unique constraint on (module_id, phase_code, level_order)
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_constraints
   WHERE table_name = 'CRMS_APPROVAL_FLOWS' AND constraint_name IN ('UQ_AF_PHASE_LEVEL', 'UQ_AF_LEVEL');
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_approval_flows ADD CONSTRAINT uq_af_phase_level UNIQUE (module_id, phase_code, level_order)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : uq_af_phase_level');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : unique constraint already exists');
  END IF;
END;
/

-- Step 7: Add phase_code to crms_release_approvals if missing
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists
    FROM user_tab_columns
   WHERE table_name = 'CRMS_RELEASE_APPROVALS' AND column_name = 'PHASE_CODE';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_approvals ADD (phase_code VARCHAR2(20) DEFAULT ''RD'')';
    DBMS_OUTPUT.PUT_LINE('  ADDED   : crms_release_approvals.phase_code');
    -- Migrate from flow_type if it exists
    SELECT COUNT(*) INTO v_exists
      FROM user_tab_columns
     WHERE table_name = 'CRMS_RELEASE_APPROVALS' AND column_name = 'FLOW_TYPE';
    IF v_exists > 0 THEN
      EXECUTE IMMEDIATE 'UPDATE crms_release_approvals SET phase_code = flow_type WHERE phase_code IS NULL';
      DBMS_OUTPUT.PUT_LINE('  MIGRATED: release_approvals flow_type -> phase_code');
    END IF;
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : crms_release_approvals.phase_code exists');
  END IF;
END;
/

-- Step 8: Ensure crms_approval_flow_approvers table exists
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
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : crms_approval_flow_approvers exists');
  END IF;
END;
/

COMMIT;

-- Verification
DECLARE
  PROCEDURE show_cols(p_table VARCHAR2) IS
  BEGIN
    FOR rec IN (SELECT column_name, data_type, nullable FROM user_tab_columns WHERE table_name = p_table ORDER BY column_id) LOOP
      DBMS_OUTPUT.PUT_LINE('    ' || RPAD(rec.column_name,25) || rec.data_type || CASE WHEN rec.nullable='N' THEN ' NOT NULL' END);
    END LOOP;
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE(CHR(10) || '===========================================');
  DBMS_OUTPUT.PUT_LINE('VERIFICATION - crms_approval_flows columns:');
  DBMS_OUTPUT.PUT_LINE('===========================================');
  show_cols('CRMS_APPROVAL_FLOWS');
  DBMS_OUTPUT.PUT_LINE('---');
  DBMS_OUTPUT.PUT_LINE('crms_approval_flow_approvers columns:');
  show_cols('CRMS_APPROVAL_FLOW_APPROVERS');
  DBMS_OUTPUT.PUT_LINE('===========================================');
  DBMS_OUTPUT.PUT_LINE('Done. Restart the Node.js server (npm run dev)');
  DBMS_OUTPUT.PUT_LINE('===========================================');
END;
/
