-- ============================================================
-- CRMS Sub-Task V4 changes
-- Run as APPS user in SQL Developer
-- ============================================================
SET SERVEROUTPUT ON
SET DEFINE OFF

-- Add delay_reason column
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns
   WHERE table_name='CRMS_RELEASE_TASKS' AND column_name='DELAY_REASON';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_release_tasks ADD delay_reason VARCHAR2(2000)';
    DBMS_OUTPUT.PUT_LINE('Added: delay_reason');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Already exists: delay_reason');
  END IF;
END;
/

COMMIT;

-- Verify
SELECT column_name, data_type, data_length, nullable
  FROM user_tab_columns
 WHERE table_name = 'CRMS_RELEASE_TASKS'
   AND column_name IN ('ACTUAL_START_DATE','ACTUAL_END_DATE','DELAY_REASON',
                       'PLANNED_START_DATE','PLANNED_END_DATE')
 ORDER BY column_name;
