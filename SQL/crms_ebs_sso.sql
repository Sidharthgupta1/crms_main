-- ============================================================
-- CRMS EBS SSO — Database Setup
-- Run as APPS user in SQL Developer on ebs_MSWILDEV
-- ============================================================
SET SERVEROUTPUT ON
SET DEFINE OFF

-- 1. Add oracle_username column to crms_users
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns
   WHERE table_name='CRMS_USERS' AND column_name='ORACLE_USERNAME';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_users ADD oracle_username VARCHAR2(100)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_crms_users_oracle ON crms_users(UPPER(oracle_username))';
    DBMS_OUTPUT.PUT_LINE('Added: oracle_username column + index');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Already exists: oracle_username');
  END IF;
END;
/

-- 2. Map existing CRMS users to their Oracle EBS usernames
--    EDIT THESE VALUES to match your actual Oracle EBS usernames
--    Oracle EBS username = what users type at the EBS login screen
UPDATE crms_users SET oracle_username = 'SANDEEP.GUPTA'  WHERE initials = 'SG';
UPDATE crms_users SET oracle_username = 'ROHIT.KUMAR'    WHERE initials = 'RK';
UPDATE crms_users SET oracle_username = 'PRIYA.MEHTA'    WHERE initials = 'PM';
UPDATE crms_users SET oracle_username = 'AMIT.VERMA'     WHERE initials = 'AV';
COMMIT;

-- 3. Verify
SELECT initials, full_name, oracle_username, role, is_active
  FROM crms_users
 ORDER BY initials;

DBMS_OUTPUT.PUT_LINE('');
DBMS_OUTPUT.PUT_LINE('EBS SSO setup complete.');
DBMS_OUTPUT.PUT_LINE('Next step: Set SSO_SHARED_SECRET in crms-backend/.env');
DBMS_OUTPUT.PUT_LINE('Then register CRMS URL in Oracle EBS as a Function (System Administrator > Application > Function)');
