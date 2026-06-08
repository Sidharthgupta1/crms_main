-- ============================================================
-- CRMS — FND_USER Sync + Password Reset
-- Run as APPS user in Toad / SQL Developer
--
-- What this does in one go:
--   1. Adds fnd_user_name column to crms_users (if not exists)
--   2. Maps existing CRMS users → FND_USER oracle usernames
--   3. Resets all passwords:
--        Admin (SG) → admin123
--        All others → pass123
--   4. Auto-imports every active FND_USER not yet in crms_users
--      (default password: pass123)
--
-- After running, any Oracle EBS user can login to CRMS with:
--   Username : their Oracle EBS username (e.g. JOHN.SMITH)
--   Password : pass123  (admin: admin123)
-- ============================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR CONTINUE

-- ── STEP 1: Add fnd_user_name column ─────────────────────────────────
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns
   WHERE table_name='CRMS_USERS' AND column_name='FND_USER_NAME';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_users ADD fnd_user_name VARCHAR2(100)';
    DBMS_OUTPUT.PUT_LINE('Added column: fnd_user_name');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Column fnd_user_name already exists — skipping');
  END IF;
END;
/

-- Add unique index (skip if exists)
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_indexes WHERE index_name='IDX_CRMS_FND_UNAME';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX idx_crms_fnd_uname ON crms_users(UPPER(fnd_user_name))';
    DBMS_OUTPUT.PUT_LINE('Index created: idx_crms_fnd_uname');
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- ── STEP 2: Map existing users to their Oracle EBS usernames ──────────
-- Edit these values to match your actual Oracle EBS usernames
-- To find them: SELECT user_name FROM fnd_user ORDER BY user_name;

UPDATE crms_users SET fnd_user_name='SUP_5783'  WHERE initials='SG';
UPDATE crms_users SET fnd_user_name='ROHIT.KUMAR'    WHERE initials='RK';
UPDATE crms_users SET fnd_user_name='PRIYA.MEHTA'    WHERE initials='PM';
UPDATE crms_users SET fnd_user_name='AMIT.VERMA'     WHERE initials='AV';
-- Add more as needed:
-- UPDATE crms_users SET fnd_user_name='ORACLE.USERNAME' WHERE initials='XX';

DBMS_OUTPUT.PUT_LINE('Existing users mapped to FND_USER usernames');

-- ── STEP 3: Reset all passwords ───────────────────────────────────────
-- admin123  → bcrypt hash (rounds=12)
UPDATE crms_users
   SET password_hash='$2b$12$oEuTYodpCwEmg9Sm4byAyOe7wYBQlK7dxULtVaeEKnBwuQOx/pHm2'
 WHERE initials='SG';

-- pass123 → bcrypt hash (rounds=12)  
UPDATE crms_users
   SET password_hash='$2b$12$LO5bMX/h05wgtgsaOEOTWOEBYVoR6gONZTGjZm/.En4OdseFlok3u'
 WHERE initials<>'SG';

DBMS_OUTPUT.PUT_LINE('Passwords reset — admin:admin123 / others:pass123');

-- ── STEP 4: Auto-import all active FND users not yet in CRMS ─────────
DECLARE
  l_added  NUMBER := 0;
  l_skip   NUMBER := 0;
  l_init   VARCHAR2(3);
  l_suffix NUMBER;
  l_clash  NUMBER;
  l_base   VARCHAR2(3);
  l_name   VARCHAR2(200);
  -- pass123 bcrypt hash
  l_hash   CONSTANT VARCHAR2(255) :=
    '$2b$12$LO5bMX/h05wgtgsaOEOTWOEBYVoR6gONZTGjZm/.En4OdseFlok3u';
BEGIN
  FOR fnd IN (
    SELECT f.user_name,
           NVL(
             NULLIF(TRIM(f.description),''),
             INITCAP(REPLACE(REPLACE(f.user_name,'.',' '),'_',' '))
           ) AS display_name
      FROM fnd_user f
     WHERE NVL(f.end_date, SYSDATE+1) > SYSDATE
       AND f.user_name NOT IN ('GUEST','INITIAL SETUP','SYSADMIN','ANONYMOUS','CONCURRENT MANAGER')
       AND NOT EXISTS (
             SELECT 1 FROM crms_users c
              WHERE UPPER(c.fnd_user_name) = UPPER(f.user_name)
           )
     ORDER BY f.user_name
  ) LOOP
    BEGIN
      -- Build initials from username words
      l_name   := REPLACE(REPLACE(fnd.user_name,'.',' '),'_',' ');
      l_base   := '';
      FOR i IN 1..LEAST(3, REGEXP_COUNT(l_name,'[^ ]+')+1) LOOP
        l_base := l_base || UPPER(SUBSTR(TRIM(REGEXP_SUBSTR(l_name,'[^ ]+',1,i)),1,1));
      END LOOP;
      IF l_base IS NULL OR LENGTH(l_base)=0 THEN l_base := UPPER(SUBSTR(fnd.user_name,1,2)); END IF;

      -- Make initials unique
      l_init   := l_base;
      l_suffix := 0;
      LOOP
        SELECT COUNT(*) INTO l_clash FROM crms_users WHERE UPPER(initials)=UPPER(l_init);
        EXIT WHEN l_clash=0;
        l_suffix := l_suffix + 1;
        l_init   := SUBSTR(l_base,1,2) || TO_CHAR(l_suffix);
      END LOOP;

      INSERT INTO crms_users
        (initials, full_name, role, password_hash, fnd_user_name, is_active, created_at)
      VALUES
        (l_init, SUBSTR(fnd.display_name,1,200), 'user',
         l_hash, UPPER(fnd.user_name), 1, SYSDATE);

      l_added := l_added + 1;
    EXCEPTION
      WHEN DUP_VAL_ON_INDEX THEN l_skip := l_skip + 1;
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('  Skipped ' || fnd.user_name || ': ' || SQLERRM);
        l_skip := l_skip + 1;
    END;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Auto-imported ' || l_added || ' FND users, skipped ' || l_skip);
END;
/

COMMIT;

-- ── STEP 5: Verify result ─────────────────────────────────────────────
PROMPT
PROMPT === CRMS Users with Oracle EBS Mapping ===
SELECT
  cu.initials,
  cu.full_name,
  cu.fnd_user_name                                          AS oracle_username,
  cu.role,
  CASE cu.initials WHEN 'SG' THEN 'admin123' ELSE 'pass123' END AS default_pwd,
  CASE WHEN fu.user_id IS NOT NULL THEN '✓ Linked'
       ELSE '✗ Not in FND_USER' END                        AS fnd_status
FROM crms_users cu
LEFT JOIN fnd_user fu
  ON UPPER(fu.user_name) = UPPER(cu.fnd_user_name)
 AND NVL(fu.end_date, SYSDATE+1) > SYSDATE
WHERE cu.is_active = 1
ORDER BY cu.role DESC, cu.full_name;

PROMPT
PROMPT ============================================================
PROMPT Done. Login to CRMS using:
PROMPT   Username : Oracle EBS username  (e.g. JOHN.SMITH)
PROMPT   Password : pass123              (admin: admin123)
PROMPT ============================================================
