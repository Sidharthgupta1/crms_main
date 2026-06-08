-- ============================================================
-- Add CEMLI, Smartsheet ID, Process Name to crms_release_tasks
-- Run as APPS user on ebs_MSWILDEV
-- ============================================================
SET SERVEROUTPUT ON
BEGIN
  FOR col IN (
    SELECT * FROM (
      SELECT 'CEMLI'          AS cn, 'VARCHAR2(200)' AS dt FROM dual UNION ALL
      SELECT 'SMARTSHEET_ID',         'VARCHAR2(200)'        FROM dual UNION ALL
      SELECT 'PROCESS_NAME',          'VARCHAR2(500)'        FROM dual
    )
  ) LOOP
    DECLARE v NUMBER;
    BEGIN
      SELECT COUNT(*) INTO v FROM user_tab_columns
      WHERE table_name='CRMS_RELEASE_TASKS' AND column_name=col.cn;
      IF v=0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE crms_release_tasks ADD '||col.cn||' '||col.dt;
        DBMS_OUTPUT.PUT_LINE('ADDED: '||col.cn);
      ELSE
        DBMS_OUTPUT.PUT_LINE('EXISTS: '||col.cn);
      END IF;
    END;
  END LOOP;
END;
/
COMMIT;
DBMS_OUTPUT.PUT_LINE('Done.');
