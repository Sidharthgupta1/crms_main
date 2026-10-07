-- ============================================================
-- CRMS_USERS.CC_EMAIL_ADDRESS
-- ============================================================
-- Run this once against the CRMS schema. Idempotent — safe to re-run.
--
-- EMAIL_ADDRESS (pre-existing, not tracked in crms_ddl.sql — added
-- out-of-band before this script) is the "To" address for CRMS mail.
-- CC_EMAIL_ADDRESS is new: an optional ';'-separated list of addresses
-- to carbon-copy whenever this user is emailed by CRMS (e.g. a manager
-- or a shared team mailbox). NULL means no CC for that user.
--
-- Example: UPDATE crms_users SET cc_email_address =
--   'manager@motherson.com;team-distro@motherson.com' WHERE user_id = 101;

DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists
    FROM user_tab_columns
   WHERE table_name = 'CRMS_USERS' AND column_name = 'CC_EMAIL_ADDRESS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_users ADD cc_email_address VARCHAR2(500)';
    DBMS_OUTPUT.PUT_LINE('  ADDED   : crms_users.cc_email_address');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : crms_users.cc_email_address (exists)');
  END IF;
END;
/
