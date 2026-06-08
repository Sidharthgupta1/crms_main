-- ============================================================
-- CRMS CRITICAL FIX — Run this in SQL Developer as APPS user
-- Fixes: ORA-12899 value too large for column
-- Root cause: 'Deployment Awaiting Approval L1' = 31 chars
--             but from_state/to_state are VARCHAR2(30)
-- ============================================================

SET SERVEROUTPUT ON

-- Step 1: Expand state columns in crms_release_history
BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE crms_release_history MODIFY from_state VARCHAR2(60)';
  DBMS_OUTPUT.PUT_LINE('OK: crms_release_history.from_state expanded to VARCHAR2(60)');
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('INFO: from_state — ' || SQLERRM);
END;
/

BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE crms_release_history MODIFY to_state VARCHAR2(60)';
  DBMS_OUTPUT.PUT_LINE('OK: crms_release_history.to_state expanded to VARCHAR2(60)');
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('INFO: to_state — ' || SQLERRM);
END;
/

-- Step 2: Verify
SELECT column_name, data_type, data_length
FROM   user_tab_columns
WHERE  table_name = 'CRMS_RELEASE_HISTORY'
  AND  column_name IN ('FROM_STATE','TO_STATE')
ORDER  BY column_name;

