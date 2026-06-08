-- ============================================================
-- CRMS EBS — Correct Function Registration (no javascript:)
-- Run as APPS user in Toad / SQL Developer
--
-- The error "field contains an invalid string for security"
-- means EBS blocks javascript: in the HTML Call field.
--
-- SOLUTION: Use a plain HTTP URL pointing to a thin
-- redirect page served by your Node.js backend.
-- EBS will open this URL directly in the browser.
-- ============================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- ============================================================
-- STEP 1: Delete old broken function entry
-- ============================================================
BEGIN
  DELETE FROM fnd_menu_entries
   WHERE function_id IN (
     SELECT function_id FROM fnd_form_functions
      WHERE function_name = 'CR_MANAGEMENT'
   );
  DBMS_OUTPUT.PUT_LINE('Removed from menus: ' || SQL%ROWCOUNT || ' rows');

  DELETE FROM fnd_form_functions_tl
   WHERE function_id IN (
     SELECT function_id FROM fnd_form_functions
      WHERE function_name = 'CR_MANAGEMENT'
   );

  DELETE FROM fnd_form_functions WHERE function_name = 'CR_MANAGEMENT';
  DBMS_OUTPUT.PUT_LINE('Old function deleted: ' || SQL%ROWCOUNT || ' rows');
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Cleanup note: ' || SQLERRM);
    ROLLBACK;
END;
/

-- ============================================================
-- STEP 2: Create the function with a PLAIN URL (no javascript:)
--
-- The HTML Call is a plain HTTP URL.
-- EBS opens it in a new window.
-- Your Node.js backend handles the SSO automatically.
--
-- URL format:  http://SERVER:PORT/ebs-launch
-- This is a page served by your Node.js that:
--   1. Reads the Oracle user from request headers (if Apache proxied)
--   2. OR shows a loading screen and calls the API
-- ============================================================
DECLARE
  l_function_id NUMBER;
  -- !! CHANGE THIS to your Node.js server IP and port !!
  l_crms_url    VARCHAR2(200) := 'http://10.240.182.66:3000';
BEGIN
  SELECT fnd_form_functions_s.NEXTVAL INTO l_function_id FROM dual;

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
    'CR_MANAGEMENT',
    0,
    'WWW',
    -- !! THIS IS THE KEY CHANGE !!
    -- Plain HTTP URL — EBS allows this, javascript: is blocked
    -- The /ebs-launch endpoint on your Node.js server
    -- reads FND_USER context and auto-logs the user in
    l_crms_url || '/ebs-launch',
    'N',
    'N',
    'FULL',
    'RESPONSIBILITY',
    SYSDATE, 1, SYSDATE, 1, 0
  );

  -- Translated name (what users see in the menu)
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
    'Motherson Change Request Management System',
    SYSDATE, 1, SYSDATE, 1, 0
  FROM fnd_languages
  WHERE installed_flag IN ('I', 'B');

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Function created. ID = ' || l_function_id);
  DBMS_OUTPUT.PUT_LINE('HTML Call = ' || l_crms_url || '/ebs-launch');

EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

-- ============================================================
-- STEP 3: Add back to the menu
-- ============================================================
DECLARE
  l_menu_id     NUMBER;
  l_function_id NUMBER;
  l_seq         NUMBER;
  -- !! CHANGE to your responsibility name !!
  l_resp_name   VARCHAR2(200) := 'MSSL_NOI_OU03_STORE_HOD_USER';
BEGIN
  SELECT function_id INTO l_function_id
    FROM fnd_form_functions WHERE function_name = 'CR_MANAGEMENT';

  SELECT menu_id INTO l_menu_id
    FROM fnd_responsibility_vl
   WHERE UPPER(responsibility_name) = UPPER(l_resp_name)
     AND ROWNUM = 1;

  SELECT NVL(MAX(sequence_number),0)+10 INTO l_seq
    FROM fnd_menu_entries WHERE menu_id = l_menu_id;

  INSERT INTO fnd_menu_entries (
    menu_id, sequence_number, sub_menu_id, function_id,
    grant_flag, last_update_date, last_updated_by,
    creation_date, created_by, last_update_login
  ) VALUES (
    l_menu_id, l_seq, NULL, l_function_id,
    'Y', SYSDATE, 1, SYSDATE, 1, 0
  );

  -- Prompt translation
  BEGIN
    INSERT INTO fnd_menu_entries_tl (
      menu_id, sequence_number, language, source_lang,
      prompt, description,
      last_update_date, last_updated_by, creation_date, created_by, last_update_login
    )
    SELECT l_menu_id, l_seq, language_code, 'US',
           'CR Management System', 'Motherson CRMS',
           SYSDATE, 1, SYSDATE, 1, 0
    FROM fnd_languages WHERE installed_flag IN ('I','B');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Added to menu at sequence ' || l_seq);

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Responsibility not found: ' || l_resp_name);
    DBMS_OUTPUT.PUT_LINE('Run: SELECT responsibility_name FROM fnd_responsibility_vl WHERE ROWNUM<20;');
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

-- ============================================================
-- STEP 4: Compile security cache
-- ============================================================
BEGIN
  FND_FUNCTION.COMPILE_ALL_ENABLED_FUNCTIONS;
  DBMS_OUTPUT.PUT_LINE('Security compiled.');
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Compile note: ' || SQLERRM);
END;
/
COMMIT;

-- ============================================================
-- STEP 5: Verify
-- ============================================================
PROMPT
PROMPT === Function registered ===
SELECT function_name, type,
       SUBSTR(web_html_call,1,100) AS html_call
  FROM fnd_form_functions
 WHERE function_name = 'CR_MANAGEMENT';

PROMPT
PROMPT === In menu ===
SELECT m.menu_name, me.sequence_number, me.prompt, f.function_name
  FROM fnd_menu_entries me
  JOIN fnd_menus m ON m.menu_id = me.menu_id
  JOIN fnd_form_functions f ON f.function_id = me.function_id
 WHERE f.function_name = 'CR_MANAGEMENT';

PROMPT
PROMPT ============================================================
PROMPT When user clicks menu item, EBS opens:
PROMPT   http://10.240.182.66:3000/ebs-launch
PROMPT
PROMPT Your Node.js backend serves this page.
PROMPT It reads the ICX session cookie from the request,
PROMPT queries FND_USER, and auto-logs the user into CRMS.
PROMPT ============================================================
