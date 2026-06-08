-- ============================================================
-- CRMS APPROVAL FLOW V2
-- Run as: APPS user on ebs_MSWILDEV
-- Adds: flow_type (RD/FSD) to crms_approval_flows
--       Updates state constraint to include new states
--       Seeds FSD approval flows for existing modules
-- ============================================================

SET ECHO OFF
SET SERVEROUTPUT ON
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE

BEGIN
  DBMS_OUTPUT.PUT_LINE('===========================================');
  DBMS_OUTPUT.PUT_LINE('CRMS Approval Flow V2 - Starting');
  DBMS_OUTPUT.PUT_LINE('Time : ' || TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS'));
  DBMS_OUTPUT.PUT_LINE('===========================================');
END;
/

-- ============================================================
-- Step 1: Add flow_type column to crms_approval_flows
-- 'RD'  = triggered after Draft -> RD Phase
-- 'FSD' = triggered after RD approval -> FSD Phase
-- ============================================================
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists
    FROM user_tab_columns
   WHERE table_name = 'CRMS_APPROVAL_FLOWS' AND column_name = 'FLOW_TYPE';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_approval_flows ADD (flow_type VARCHAR2(10) DEFAULT ''RD'' NOT NULL)';
    DBMS_OUTPUT.PUT_LINE('  ALTERED : crms_approval_flows - added flow_type');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : flow_type already exists');
  END IF;
END;
/

-- ============================================================
-- Step 2: Add CHECK constraint on flow_type
-- ============================================================
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_constraints
   WHERE table_name = 'CRMS_APPROVAL_FLOWS' AND constraint_name = 'CHK_AF_FLOW_TYPE';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_approval_flows ADD CONSTRAINT chk_af_flow_type CHECK (flow_type IN (''RD'',''FSD''))';
    DBMS_OUTPUT.PUT_LINE('  CREATED : chk_af_flow_type constraint');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : chk_af_flow_type already exists');
  END IF;
END;
/

-- ============================================================
-- Step 3: Drop old unique constraint on (module_id, level_order)
-- because we now need (module_id, flow_type, level_order) unique
-- ============================================================
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

DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_constraints
   WHERE table_name = 'CRMS_APPROVAL_FLOWS' AND constraint_name = 'UQ_FLOW_TYPE_LEVEL';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_approval_flows ADD CONSTRAINT uq_flow_type_level UNIQUE (module_id, flow_type, level_order)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : uq_flow_type_level');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : uq_flow_type_level exists');
  END IF;
END;
/

-- ============================================================
-- Step 4: Add flow_type column to crms_release_approvals
-- so we can track which gate (RD or FSD) this approval belongs to
-- ============================================================
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists
    FROM user_tab_columns
   WHERE table_name = 'CRMS_RELEASE_APPROVALS' AND column_name = 'FLOW_TYPE';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_approvals ADD (flow_type VARCHAR2(10) DEFAULT ''RD'' NOT NULL)';
    DBMS_OUTPUT.PUT_LINE('  ALTERED : crms_release_approvals - added flow_type');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : crms_release_approvals.flow_type exists');
  END IF;
END;
/

-- ============================================================
-- Step 5: Update state constraint to include FSD Awaiting Approval states
-- ============================================================
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_constraints
   WHERE table_name = 'CRMS_RELEASES' AND constraint_name = 'CHK_RELEASE_STATE';
  IF v_exists > 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases DROP CONSTRAINT chk_release_state';
    DBMS_OUTPUT.PUT_LINE('  DROPPED : chk_release_state');
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
        'FSD Phase',
        'FSD Awaiting Approval L1','FSD Awaiting Approval L2','FSD Awaiting Approval L3',
        'FSD Awaiting Approval L4','FSD Awaiting Approval L5',
        'On Hold','Development Phase','Testing/QA','UAT','Deployment','Closed','Cancelled'
      ))]';
    DBMS_OUTPUT.PUT_LINE('  CREATED : chk_release_state (v2 with RD+FSD approval states)');
  END IF;
END;
/

-- ============================================================
-- Step 6: Seed FSD approval flows for Manufacturing module
-- (same approvers as RD for demo — admin can change in Modules UI)
-- ============================================================
DECLARE
  v_mfg_id NUMBER;
  v_pur_id  NUMBER;
  v_sg_id   NUMBER;
  v_pm_id   NUMBER;
  v_av_id   NUMBER;
BEGIN
  BEGIN SELECT module_id INTO v_mfg_id FROM crms_modules WHERE module_name = 'Manufacturing'; EXCEPTION WHEN NO_DATA_FOUND THEN v_mfg_id := NULL; END;
  BEGIN SELECT module_id INTO v_pur_id FROM crms_modules WHERE module_name = 'Purchasing';    EXCEPTION WHEN NO_DATA_FOUND THEN v_pur_id := NULL; END;
  BEGIN SELECT user_id   INTO v_sg_id  FROM crms_users WHERE initials = 'SG';                EXCEPTION WHEN NO_DATA_FOUND THEN v_sg_id := NULL; END;
  BEGIN SELECT user_id   INTO v_pm_id  FROM crms_users WHERE initials = 'PM';                EXCEPTION WHEN NO_DATA_FOUND THEN v_pm_id := NULL; END;
  BEGIN SELECT user_id   INTO v_av_id  FROM crms_users WHERE initials = 'AV';                EXCEPTION WHEN NO_DATA_FOUND THEN v_av_id := NULL; END;

  -- Manufacturing: FSD approval L1=PM, L2=SG (same as RD)
  IF v_mfg_id IS NOT NULL AND v_pm_id IS NOT NULL AND v_sg_id IS NOT NULL THEN
    MERGE INTO crms_approval_flows t
    USING (SELECT v_mfg_id AS mid, 'FSD' AS ft, 1 AS lvl, v_pm_id AS uid, 0 AS auto FROM dual) s
    ON (t.module_id=s.mid AND t.flow_type=s.ft AND t.level_order=s.lvl)
    WHEN NOT MATCHED THEN INSERT (module_id,flow_type,level_order,approver_user_id,auto_approve) VALUES (s.mid,s.ft,s.lvl,s.uid,s.auto);

    MERGE INTO crms_approval_flows t
    USING (SELECT v_mfg_id AS mid, 'FSD' AS ft, 2 AS lvl, v_sg_id AS uid, 0 AS auto FROM dual) s
    ON (t.module_id=s.mid AND t.flow_type=s.ft AND t.level_order=s.lvl)
    WHEN NOT MATCHED THEN INSERT (module_id,flow_type,level_order,approver_user_id,auto_approve) VALUES (s.mid,s.ft,s.lvl,s.uid,s.auto);

    DBMS_OUTPUT.PUT_LINE('  SEEDED  : Manufacturing FSD approval flow');
  END IF;

  -- Purchasing: FSD approval L1=AV, auto_approve=1
  IF v_pur_id IS NOT NULL AND v_av_id IS NOT NULL THEN
    MERGE INTO crms_approval_flows t
    USING (SELECT v_pur_id AS mid, 'FSD' AS ft, 1 AS lvl, v_av_id AS uid, 1 AS auto FROM dual) s
    ON (t.module_id=s.mid AND t.flow_type=s.ft AND t.level_order=s.lvl)
    WHEN NOT MATCHED THEN INSERT (module_id,flow_type,level_order,approver_user_id,auto_approve) VALUES (s.mid,s.ft,s.lvl,s.uid,s.auto);

    DBMS_OUTPUT.PUT_LINE('  SEEDED  : Purchasing FSD approval flow (auto)');
  END IF;
END;
/

-- ============================================================
-- Step 7: Mark existing approval flows as RD type
-- ============================================================
UPDATE crms_approval_flows SET flow_type = 'RD' WHERE flow_type IS NULL OR flow_type = 'RD';
DBMS_OUTPUT.PUT_LINE('  UPDATED : Existing flows marked as RD type');

COMMIT;

-- ============================================================
-- VERIFICATION
-- ============================================================
DECLARE
  PROCEDURE show_count(p_table VARCHAR2) IS
    v_cnt NUMBER;
  BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || p_table INTO v_cnt;
    DBMS_OUTPUT.PUT_LINE('  ' || RPAD(p_table,35) || ' : ' || v_cnt || ' rows');
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  ' || RPAD(p_table,35) || ' : ERROR - ' || SQLERRM);
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE(CHR(10) || '===========================================');
  DBMS_OUTPUT.PUT_LINE('Approval Flow V2 Row Counts:');
  DBMS_OUTPUT.PUT_LINE('===========================================');
  show_count('crms_approval_flows');
  show_count('crms_release_approvals');
  DBMS_OUTPUT.PUT_LINE('===========================================');
  DBMS_OUTPUT.PUT_LINE('Done. FSD approval flows seeded.');
  DBMS_OUTPUT.PUT_LINE('===========================================');
END;
/
