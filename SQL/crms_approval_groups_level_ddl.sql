-- ============================================================
-- Add level_order to crms_approval_groups
-- Allows multiple groups per phase/level (e.g. L1 can have Group A + Group B)
-- Run as APPS user on ebs_MSWILDEV
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns
  WHERE table_name='CRMS_APPROVAL_GROUPS' AND column_name='LEVEL_ORDER';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_approval_groups ADD level_order NUMBER DEFAULT 1 NOT NULL';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_apgrp_level ON crms_approval_groups(phase_code,level_order)';
    DBMS_OUTPUT.PUT_LINE('ADDED: level_order to crms_approval_groups');
  ELSE
    DBMS_OUTPUT.PUT_LINE('EXISTS: level_order already in crms_approval_groups');
  END IF;
END;
/
-- Update any existing rows to level 1
UPDATE crms_approval_groups SET level_order=1 WHERE level_order IS NULL;
COMMIT;
DBMS_OUTPUT.PUT_LINE('Done.');
