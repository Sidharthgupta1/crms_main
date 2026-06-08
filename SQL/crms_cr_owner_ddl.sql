-- ============================================================
-- CRMS CR Owner — DDL
-- Run as APPS user on ebs_MSWILDEV
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns
  WHERE table_name='CRMS_RELEASES' AND column_name='CR_OWNER_USER_ID';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases ADD cr_owner_user_id NUMBER CONSTRAINT fk_rel_cr_owner REFERENCES crms_users(user_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rel_cr_owner ON crms_releases(cr_owner_user_id)';
    DBMS_OUTPUT.PUT_LINE('CREATED: cr_owner_user_id column on crms_releases');
  ELSE
    DBMS_OUTPUT.PUT_LINE('EXISTS:  cr_owner_user_id column');
  END IF;
END;
/
COMMIT;
