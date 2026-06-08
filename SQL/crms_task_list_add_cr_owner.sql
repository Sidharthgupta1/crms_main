-- Add cr_owner to existing crms_task_list table (if not already added)
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns
  WHERE table_name='CRMS_TASK_LIST' AND column_name='CR_OWNER';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_task_list ADD cr_owner VARCHAR2(200)';
    DBMS_OUTPUT.PUT_LINE('CREATED: cr_owner column on crms_task_list');
  ELSE
    DBMS_OUTPUT.PUT_LINE('EXISTS:  cr_owner column');
  END IF;
END;
/
COMMIT;
