-- Add CEMLI, SmartsheetID, ProcessName to crms_releases
DECLARE
BEGIN
  FOR col IN (
    SELECT * FROM (
      SELECT 'CEMLI' AS cn, 'VARCHAR2(200)' AS dt FROM dual UNION ALL
      SELECT 'SMARTSHEET_ID', 'VARCHAR2(200)' FROM dual UNION ALL
      SELECT 'PROCESS_NAME', 'VARCHAR2(500)' FROM dual
    )
  ) LOOP
    DECLARE v NUMBER;
    BEGIN
      SELECT COUNT(*) INTO v FROM user_tab_columns
      WHERE table_name='CRMS_RELEASES' AND column_name=col.cn;
      IF v=0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE crms_releases ADD '||col.cn||' '||col.dt;
        DBMS_OUTPUT.PUT_LINE('ADDED: '||col.cn||' to CRMS_RELEASES');
      ELSE
        DBMS_OUTPUT.PUT_LINE('EXISTS: '||col.cn);
      END IF;
    END;
  END LOOP;
END;
/
COMMIT;
