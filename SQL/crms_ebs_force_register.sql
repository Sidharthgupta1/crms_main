-- ============================================================
-- CRMS EBS Force Registration — Complete Reset & Re-register
-- Run as APPS user in Toad / SQL Developer
--
-- This script:
-- 1. Deletes and recreates the CRMS function cleanly
-- 2. Adds it directly to the responsibility's menu
-- 3. Compiles security so it appears immediately
-- 4. Verifies everything is correct
--
-- BEFORE RUNNING:
--   Change line marked *** to your actual CRMS server address
--   Change line marked ### to your actual Responsibility name
-- ============================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR CONTINUE

-- ============================================================
-- PART 1: Clean up any broken previous registration
-- ============================================================
BEGIN
  -- Remove from all menus first
  DELETE FROM fnd_menu_entries
  WHERE function_id IN (
    SELECT function_id FROM fnd_form_functions
    WHERE function_name = 'CRMS_MAIN'
  );
  DBMS_OUTPUT.PUT_LINE('Removed from menus: ' || SQL%ROWCOUNT || ' entries deleted');

  -- Remove the function itself
  DELETE FROM fnd_form_functions_tl
  WHERE function_id IN (
    SELECT function_id FROM fnd_form_functions
    WHERE function_name = 'CRMS_MAIN'
  );

  DELETE FROM fnd_form_functions
  WHERE function_name = 'CRMS_MAIN';

  DBMS_OUTPUT.PUT_LINE('Function removed: ' || SQL%ROWCOUNT || ' rows deleted');
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Cleanup note: ' || SQLERRM);
    ROLLBACK;
END;
/

-- ============================================================
-- PART 2: Create the CRMS function fresh using direct INSERT
-- (More reliable than FND_FUNCTION API for some EBS versions)
-- ============================================================
DECLARE
  l_function_id  NUMBER;
  l_crms_url     VARCHAR2(500);
BEGIN
  -- *** CHANGE THIS to your actual CRMS server IP and port ***
  l_crms_url := 'http://10.240.182.66:3000';
  -- Examples:
  -- l_crms_url := 'http://10.0.0.50:3000';
  -- l_crms_url := 'http://crms.motherson.internal:3000';

  -- Get next function_id from sequence
  SELECT fnd_form_functions_s.NEXTVAL INTO l_function_id FROM dual;

  -- Insert the function record
  INSERT INTO fnd_form_functions (
    function_id,
    function_name,
    application_id,
    type,
    web_html_call,
    web_encrypt_parameters,
    web_secured,
    maintenance_mode_support,
    context_dependence,
    last_update_date,
    last_updated_by,
    creation_date,
    created_by,
    last_update_login
  ) VALUES (
    l_function_id,
    'CRMS_MAIN',
    0,                    -- 0 = not tied to a specific application
    'WWW',
    -- The HTML that runs when user clicks the menu item
    -- Opens CRMS in a new popup window
    'javascript:void(window.open(''' || l_crms_url ||
    ''',''crms_window'',''width=1400,height=900,scrollbars=yes,resizable=yes,toolbar=no,menubar=no''))',
    'N',
    'N',
    'FULL',
    'RESPONSIBILITY',
    SYSDATE,
    1,
    SYSDATE,
    1,
    0
  );

  -- Insert the translated name (what users see)
  INSERT INTO fnd_form_functions_tl (
    function_id,
    language,
    source_lang,
    user_function_name,
    description,
    last_update_date,
    last_updated_by,
    creation_date,
    created_by,
    last_update_login
  )
  SELECT
    l_function_id,
    language_code,
    'US',
    'CR Management System',
    'Motherson CR Management System — Change Request Tool',
    SYSDATE, 1, SYSDATE, 1, 0
  FROM fnd_languages
  WHERE installed_flag IN ('I', 'B');

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('SUCCESS: Function created. ID = ' || l_function_id);
  DBMS_OUTPUT.PUT_LINE('Function URL: ' || l_crms_url);

EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('ERROR creating function: ' || SQLERRM);
END;
/

-- ============================================================
-- PART 3: Add CRMS to the RESPONSIBILITY's menu directly
-- Find the right menu first, then add the entry
-- ============================================================
DECLARE
  l_menu_id     NUMBER;
  l_function_id NUMBER;
  l_seq         NUMBER;
  l_resp_name   VARCHAR2(200);
BEGIN
  -- ### CHANGE THIS to the exact Responsibility name you login with ###
  -- Find it: SELECT responsibility_name FROM fnd_responsibility_vl WHERE ROWNUM < 20;
  l_resp_name := 'System Administrator';
  -- Other examples:
  -- l_resp_name := 'MSSL IT Administrator';
  -- l_resp_name := 'Oracle Super User';

  -- Get function ID
  SELECT function_id INTO l_function_id
    FROM fnd_form_functions
   WHERE function_name = 'CRMS_MAIN';

  -- Get the menu_id from the responsibility
  SELECT menu_id INTO l_menu_id
    FROM fnd_responsibility_vl
   WHERE UPPER(responsibility_name) = UPPER(l_resp_name)
     AND ROWNUM = 1;

  DBMS_OUTPUT.PUT_LINE('Responsibility: ' || l_resp_name);
  DBMS_OUTPUT.PUT_LINE('Menu ID: ' || l_menu_id);

  -- Check if already in menu
  DECLARE
    l_exists NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_exists
      FROM fnd_menu_entries
     WHERE menu_id = l_menu_id
       AND function_id = l_function_id;

    IF l_exists > 0 THEN
      DBMS_OUTPUT.PUT_LINE('Already in menu — removing and re-adding...');
      DELETE FROM fnd_menu_entries
       WHERE menu_id = l_menu_id AND function_id = l_function_id;
    END IF;
  END;

  -- Get next sequence number
  SELECT NVL(MAX(sequence_number), 0) + 10 INTO l_seq
    FROM fnd_menu_entries
   WHERE menu_id = l_menu_id;

  -- Add CRMS to the menu
  INSERT INTO fnd_menu_entries (
    menu_id,
    sequence_number,
    sub_menu_id,
    function_id,
    grant_flag,
    last_update_date,
    last_updated_by,
    creation_date,
    created_by,
    last_update_login
  ) VALUES (
    l_menu_id,
    l_seq,
    NULL,
    l_function_id,
    'Y',
    SYSDATE,
    1,
    SYSDATE,
    1,
    0
  );

  -- Add the translated prompt (menu label)
  -- fnd_menu_entries_tl may not exist in all EBS versions — skip if error
  BEGIN
    INSERT INTO fnd_menu_entries_tl (
      menu_id,
      sequence_number,
      language,
      source_lang,
      prompt,
      description,
      last_update_date,
      last_updated_by,
      creation_date,
      created_by,
      last_update_login
    )
    SELECT
      l_menu_id,
      l_seq,
      language_code,
      'US',
      'CR Management System',
      'Motherson CR Management System',
      SYSDATE, 1, SYSDATE, 1, 0
    FROM fnd_languages
    WHERE installed_flag IN ('I', 'B');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TL table note: ' || SQLERRM);
  END;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('SUCCESS: CRMS added to menu at sequence ' || l_seq);

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('ERROR: Responsibility "' || l_resp_name || '" not found.');
    DBMS_OUTPUT.PUT_LINE('Run this to see available responsibilities:');
    DBMS_OUTPUT.PUT_LINE('SELECT responsibility_name FROM fnd_responsibility_vl WHERE ROWNUM < 30 ORDER BY responsibility_name;');
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
END;
/

-- ============================================================
-- PART 4: Force compile security — makes it visible NOW
-- ============================================================
BEGIN
  DBMS_OUTPUT.PUT_LINE('Compiling security...');

  -- This is the key step that rebuilds the compiled menu cache
  -- fnd_compiled_menu_functions gets rebuilt from this
  FND_FUNCTION.COMPILE_ALL_ENABLED_FUNCTIONS;

  DBMS_OUTPUT.PUT_LINE('Security compiled.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Compile note: ' || SQLERRM);
END;
/
COMMIT;

-- ============================================================
-- PART 5: Also update the compiled functions table directly
-- ============================================================
DECLARE
  l_function_id NUMBER;
BEGIN
  SELECT function_id INTO l_function_id
    FROM fnd_form_functions WHERE function_name = 'CRMS_MAIN';

  -- Directly insert into compiled menu functions for ALL responsibilities
  -- that have this menu
  MERGE INTO fnd_compiled_menu_functions cf
  USING (
    SELECT DISTINCT r.responsibility_id, l_function_id AS fid
      FROM fnd_responsibility r
      JOIN fnd_menu_entries me ON me.menu_id = r.menu_id
     WHERE me.function_id = l_function_id
  ) src
  ON (cf.responsibility_id = src.responsibility_id AND cf.function_id = src.fid)
  WHEN NOT MATCHED THEN
    INSERT (responsibility_id, function_id)
    VALUES (src.responsibility_id, src.fid);

  DBMS_OUTPUT.PUT_LINE('Compiled menu functions updated: ' || SQL%ROWCOUNT || ' rows');
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Compiled functions note: ' || SQLERRM);
    ROLLBACK;
END;
/

-- ============================================================
-- PART 6: Final verification
-- ============================================================
PROMPT
PROMPT === Verification: CRMS Function ===
SELECT function_id, function_name, user_function_name, type,
       SUBSTR(web_html_call,1,80) AS url_preview
  FROM fnd_form_functions
 WHERE function_name = 'CRMS_MAIN';

PROMPT
PROMPT === Verification: Menu Entry ===
SELECT m.menu_name, m.user_menu_name, me.sequence_number,
       me.grant_flag, f.function_name
  FROM fnd_menu_entries me
  JOIN fnd_menus m ON m.menu_id = me.menu_id
  JOIN fnd_form_functions f ON f.function_id = me.function_id
 WHERE f.function_name = 'CRMS_MAIN';

PROMPT
PROMPT === Verification: Compiled Security ===
SELECT r.responsibility_name, f.function_name
  FROM fnd_compiled_menu_functions cf
  JOIN fnd_form_functions f ON f.function_id = cf.function_id
  JOIN fnd_responsibility_vl r ON r.responsibility_id = cf.responsibility_id
 WHERE f.function_name = 'CRMS_MAIN'
 ORDER BY r.responsibility_name;

PROMPT
PROMPT ============================================================
PROMPT DONE. Now:
PROMPT   1. Log out of Oracle EBS completely
PROMPT   2. Close and reopen the browser
PROMPT   3. Log back in to EBS
PROMPT   4. Look for "CR Management System" in the Navigator
PROMPT ============================================================
