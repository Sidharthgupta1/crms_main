-- ============================================================
-- CRMS — Fix Bad Names in crms_users
-- Run as APPS user in Toad / SQL Developer
--
-- PROBLEM 1: Some users have full_name = '[object Object]'
--   Caused by: JavaScript object being converted to string
--   when fndRow.DESCRIPTION was an object not a string
--
-- PROBLEM 2: Some users have names containing numeric codes
--   e.g. "00123456 John Smith", "EMP98765"
--   Caused by: Oracle FND_USER.DESCRIPTION containing
--   employee IDs or HR codes alongside the real name
--
-- This script fixes both by re-deriving names from FND_USER
-- using proper name extraction logic (letters only)
-- ============================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
  l_fixed  NUMBER := 0;
  l_skip   NUMBER := 0;

  -- Extract clean name from a raw description string
  -- Strips numeric codes, keeps only alphabetic words of 2+ chars
  FUNCTION clean_name(p_raw IN VARCHAR2) RETURN VARCHAR2 IS
    l_result VARCHAR2(200) := '';
    l_words  APEX_APPLICATION_GLOBAL.VC_ARR2;
    l_word   VARCHAR2(100);
    l_clean  VARCHAR2(100);
    l_letters NUMBER;
  BEGIN
    IF p_raw IS NULL THEN RETURN NULL; END IF;

    -- Replace non-alpha (except space, dot, hyphen, apostrophe) with space
    -- Then split on spaces
    DECLARE
      l_cleaned VARCHAR2(500);
    BEGIN
      -- Remove digits and special characters, keep letters and word separators
      l_cleaned := REGEXP_REPLACE(p_raw, '[^a-zA-Z ]', ' ');
      -- Collapse multiple spaces
      l_cleaned := REGEXP_REPLACE(l_cleaned, '\s+', ' ');
      l_cleaned := TRIM(l_cleaned);

      -- Process each word
      FOR i IN 1..REGEXP_COUNT(l_cleaned, '\S+') LOOP
        l_word  := REGEXP_SUBSTR(l_cleaned, '\S+', 1, i);
        -- Count letters in this word
        l_letters := LENGTH(REGEXP_REPLACE(l_word, '[^a-zA-Z]', ''));
        -- Keep only words with 2+ letters (filters initials, single chars, junk)
        IF l_letters >= 2 THEN
          -- Title case
          l_clean := UPPER(SUBSTR(l_word, 1, 1)) || LOWER(SUBSTR(l_word, 2));
          l_result := TRIM(l_result || ' ' || l_clean);
        END IF;
      END LOOP;

      RETURN TRIM(l_result);
    END;
  END clean_name;

BEGIN
  FOR u IN (
    SELECT cu.user_id, cu.full_name, cu.fnd_user_name,
           fu.description AS fnd_desc, fu.user_name AS fnd_uname
      FROM crms_users cu
      LEFT JOIN fnd_user fu ON UPPER(fu.user_name) = UPPER(cu.fnd_user_name)
     WHERE cu.is_active = 1
       AND (
         -- Case 1: [object Object] — JavaScript serialization bug
         cu.full_name = '[object Object]'
         OR cu.full_name LIKE '%[object%'
         OR cu.full_name LIKE '%Object]%'
         -- Case 2: Name contains digits (numeric codes mixed in)
         OR REGEXP_LIKE(cu.full_name, '[0-9]')
         -- Case 3: Name is suspiciously short or empty
         OR LENGTH(TRIM(cu.full_name)) < 3
         -- Case 4: Name is all uppercase (often a username, not a display name)
         OR cu.full_name = UPPER(cu.full_name)
       )
  ) LOOP
    DECLARE
      l_new_name VARCHAR2(200);
    BEGIN
      -- Try FND_USER.DESCRIPTION first
      IF u.fnd_desc IS NOT NULL THEN
        l_new_name := clean_name(u.fnd_desc);
      END IF;

      -- Fall back to formatting the Oracle username
      IF l_new_name IS NULL OR LENGTH(TRIM(l_new_name)) < 3 THEN
        IF u.fnd_uname IS NOT NULL THEN
          -- JOHN.SMITH → John Smith
          l_new_name := clean_name(REPLACE(REPLACE(u.fnd_uname, '.', ' '), '_', ' '));
        ELSE
          -- Use fnd_user_name stored in crms_users
          l_new_name := clean_name(REPLACE(REPLACE(u.fnd_user_name, '.', ' '), '_', ' '));
        END IF;
      END IF;

      -- Only update if we got a better name
      IF l_new_name IS NOT NULL AND LENGTH(TRIM(l_new_name)) >= 3
         AND l_new_name != u.full_name THEN
        UPDATE crms_users
           SET full_name = l_new_name
         WHERE user_id = u.user_id;
        DBMS_OUTPUT.PUT_LINE('Fixed: [' || u.full_name || '] -> [' || l_new_name || '] for ' || NVL(u.fnd_user_name,'?'));
        l_fixed := l_fixed + 1;
      ELSE
        l_skip := l_skip + 1;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Skip user_id ' || u.user_id || ': ' || SQLERRM);
      l_skip := l_skip + 1;
    END;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('Fixed: ' || l_fixed || ' users');
  DBMS_OUTPUT.PUT_LINE('Skipped: ' || l_skip || ' users');
END;
/

-- Verify results
SELECT user_id, initials, full_name, fnd_user_name
  FROM crms_users
 WHERE is_active = 1
 ORDER BY full_name;
