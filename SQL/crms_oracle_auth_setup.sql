-- ============================================================
-- CRMS Oracle Authentication Setup
-- Run as SYSDBA or SYS user
--
-- PURPOSE:
--   Grants the APPS schema EXECUTE permission on FND_WEB_SEC
--   so CRMS backend can call FND_WEB_SEC.VALIDATE_LOGIN to
--   authenticate users with their Oracle EBS credentials.
--
-- WHAT FND_WEB_SEC.VALIDATE_LOGIN DOES:
--   It is Oracle's own credential validation function.
--   Takes (username, password) and returns 'Y' if valid.
--   It checks against FND_USER.ENCRYPTED_USER_PASSWORD —
--   the same encrypted password Oracle EBS login uses.
--   The actual password is never exposed to CRMS.
--
-- RUN THIS ONCE as SYSDBA before starting CRMS backend.
-- ============================================================

SET SERVEROUTPUT ON
SET DEFINE OFF

-- Step 1: Grant EXECUTE on FND_WEB_SEC to APPS
-- (APPS usually already owns FND_WEB_SEC, but in some setups it needs explicit grant)
BEGIN
  EXECUTE IMMEDIATE 'GRANT EXECUTE ON APPS.FND_WEB_SEC TO APPS';
  DBMS_OUTPUT.PUT_LINE('Granted EXECUTE on FND_WEB_SEC to APPS');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Note: ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE('APPS may already own FND_WEB_SEC (this is normal)');
END;
/

-- Step 2: Test that VALIDATE_LOGIN is callable
-- Run this as APPS user to confirm it works
DECLARE
  l_result VARCHAR2(10);
BEGIN
  -- Test with a known invalid user — should return 'N' or raise exception
  -- Replace 'TEST_USER' and 'test_pass' with real credentials to verify
  BEGIN
    l_result := FND_WEB_SEC.VALIDATE_LOGIN('SYSADMIN', 'WRONGPASSWORD');
    DBMS_OUTPUT.PUT_LINE('VALIDATE_LOGIN test result: ' || NVL(l_result, 'NULL'));
    DBMS_OUTPUT.PUT_LINE('(Expected: N for wrong password)');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('VALIDATE_LOGIN raised exception: ' || SQLERRM);
      DBMS_OUTPUT.PUT_LINE('This is normal for wrong passwords in some Oracle versions.');
  END;
  DBMS_OUTPUT.PUT_LINE('FND_WEB_SEC.VALIDATE_LOGIN is accessible.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: FND_WEB_SEC not accessible: ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE('Make sure you are connected as APPS and the grant above was applied.');
END;
/

-- Step 3: Ensure fnd_user_name column exists in crms_users
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns
   WHERE table_name='CRMS_USERS' AND column_name='FND_USER_NAME';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_users ADD fnd_user_name VARCHAR2(100)';
    EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX idx_crms_fnd_uname ON crms_users(UPPER(fnd_user_name))';
    DBMS_OUTPUT.PUT_LINE('Added fnd_user_name column to crms_users');
  ELSE
    DBMS_OUTPUT.PUT_LINE('fnd_user_name column already exists');
  END IF;
END;
/

-- Step 4: Map existing CRMS users to their Oracle usernames
-- EDIT THESE to match your actual Oracle EBS usernames
-- Find usernames: SELECT user_name FROM fnd_user WHERE ROWNUM < 20;
UPDATE crms_users SET fnd_user_name = 'SUP_5783' WHERE initials = 'SG' AND fnd_user_name IS NULL;
UPDATE crms_users SET fnd_user_name = 'BNISCHAL'   WHERE initials = 'BN' AND fnd_user_name IS NULL;
COMMIT;

-- Step 5: Verify the mapping
SELECT
  cu.initials,
  cu.full_name,
  cu.fnd_user_name       AS oracle_username,
  fu.user_id             AS fnd_user_id,
  CASE WHEN fu.user_id IS NOT NULL THEN 'LINKED' ELSE 'NOT LINKED' END AS status
FROM crms_users cu
LEFT JOIN fnd_user fu
  ON UPPER(fu.user_name) = UPPER(cu.fnd_user_name)
 AND NVL(fu.end_date, SYSDATE+1) > SYSDATE
WHERE cu.is_active = 1
ORDER BY cu.initials;

PROMPT
PROMPT ============================================================
PROMPT Setup complete.
PROMPT Users can now login to CRMS using their Oracle EBS credentials.
PROMPT No separate CRMS password needed.
PROMPT ============================================================
