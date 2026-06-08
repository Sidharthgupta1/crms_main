-- ============================================================
-- CRMS — Oracle EBS R12 Menu Registration
-- Run as APPS user in SQL Developer / Toad
-- This registers CRMS as a proper EBS function and adds it
-- to the System Administrator menu so you can see it
-- ============================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR CONTINUE

-- ============================================================
-- STEP 1: Create the EBS Function for CRMS
-- This is the "link" that EBS uses to open your tool
-- ============================================================
DECLARE
  l_function_id  NUMBER;
  l_exists       NUMBER;
BEGIN
  -- Check if function already exists
  SELECT COUNT(*) INTO l_exists
    FROM fnd_form_functions
   WHERE function_name = 'CR_MANEGMENT';

  IF l_exists > 0 THEN
    DBMS_OUTPUT.PUT_LINE('Function CR_MANEGMENT already exists — skipping creation');
    SELECT function_id INTO l_function_id
      FROM fnd_form_functions WHERE function_name = 'CR_MANEGMENT';
    DBMS_OUTPUT.PUT_LINE('Function ID: ' || l_function_id);
  ELSE
    -- Create the function
    -- CHANGE: Replace YOUR-SERVER-IP and PORT with your actual values
    -- Example: http://192.168.1.50:3000
    FND_FUNCTION.CREATE_FUNCTION(
      x_function_name       => 'CR_MANEGMENT',
      x_user_function_name  => 'CR_MANEGMENT',
      x_description         => NULL,
      x_type                => 'WWW',
      x_web_host_name       => NULL,
      x_web_agent_name      => NULL,
      x_web_html_call       => 'http://10.240.182.45:3000/api/v1/auth/ebs-sso-redirect?username=&ts=1776363354&sig=35471d04b4c2d788169adf83d313b01902f1437905d00a8ac48a93ce18375de1&redirect=/',
      x_web_encrypt_parameters => 'N',
      x_web_secured         => 'N',
      x_web_icon            => NULL,
      x_language_code       => 'US',
      x_creation_date       => SYSDATE,
      x_created_by          => 1,
      x_last_update_date    => SYSDATE,
      x_last_updated_by     => 1,
      x_last_update_login   => 0
    );

    SELECT function_id INTO l_function_id
      FROM fnd_form_functions WHERE function_name = 'CR_MANEGMENT';

    DBMS_OUTPUT.PUT_LINE('SUCCESS: Function CR_MANEGMENT created. ID = ' || l_function_id);
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR creating function: ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE('Try the manual steps in Section B below instead.');
END;
/

COMMIT;

-- ============================================================
-- STEP 2: Add CRMS to a Menu
-- We add it to SYS_ADMINISTRATOR_MENU (visible to Sys Admin)
-- You can change the menu_name to any menu your users have
-- ============================================================
DECLARE
  l_menu_id     NUMBER;
  l_function_id NUMBER;
  l_seq         NUMBER;
  l_exists      NUMBER;
BEGIN
  -- Get the function ID
  SELECT function_id INTO l_function_id
    FROM fnd_form_functions
   WHERE function_name = 'CR_MANEGMENT';

  -- Get menu ID — change 'SYS_ADMINISTRATOR_MENU' to the menu your users see
  -- Common menus:
  --   SYS_ADMINISTRATOR_MENU  = System Administrator
  --   FND_NAVIGATE4_0         = Navigator menu
  -- To find your menu: SELECT menu_name, user_menu_name FROM fnd_menus WHERE ROWNUM < 20;
  SELECT menu_id INTO l_menu_id
    FROM fnd_menus
   WHERE menu_name = 'SYS_ADMINISTRATOR_MENU';

  -- Check if already in menu
  SELECT COUNT(*) INTO l_exists
    FROM fnd_menu_entries
   WHERE menu_id = l_menu_id
     AND function_id = l_function_id;

  IF l_exists > 0 THEN
    DBMS_OUTPUT.PUT_LINE('CRMS already in menu — skipping');
  ELSE
    -- Get next sequence number
    SELECT NVL(MAX(sequence_number), 0) + 10 INTO l_seq
      FROM fnd_menu_entries WHERE menu_id = l_menu_id;

    FND_MENU_ENTRIES_PKG.INSERT_ROW(
      x_menu_id           => l_menu_id,
      x_sequence_number   => l_seq,
      x_sub_menu_id       => NULL,
      x_function_id       => l_function_id,
      x_grant_flag        => 'Y',
      x_prompt            => 'CR Management System',
      x_description       => 'Open CRMS — Change Request Management Tool',
      x_creation_date     => SYSDATE,
      x_created_by        => 1,
      x_last_update_date  => SYSDATE,
      x_last_updated_by   => 1,
      x_last_update_login => 0
    );
    DBMS_OUTPUT.PUT_LINE('SUCCESS: CRMS added to menu at sequence ' || l_seq);
  END IF;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('Menu SYS_ADMINISTRATOR_MENU not found.');
    DBMS_OUTPUT.PUT_LINE('Run this to find available menus:');
    DBMS_OUTPUT.PUT_LINE('SELECT menu_name, user_menu_name FROM fnd_menus WHERE ROWNUM < 30;');
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR adding to menu: ' || SQLERRM);
END;
/

COMMIT;

-- ============================================================
-- STEP 3: Verify what was created
-- ============================================================
SELECT
  f.function_name,
  f.user_function_name,
  f.type,
  f.web_html_call
FROM fnd_form_functions f
WHERE f.function_name = 'CR_MANEGMENT';

SELECT
  m.menu_name,
  m.user_menu_name,
  me.sequence_number,
  me.prompt,
  f.function_name
FROM fnd_menu_entries me
JOIN fnd_menus m         ON m.menu_id      = me.menu_id
JOIN fnd_form_functions f ON f.function_id = me.function_id
WHERE f.function_name = 'CR_MANEGMENT';

-- ============================================================
-- HELPER: Find which menu your responsibility uses
-- Run this to find the right menu_name for Step 2
-- ============================================================
/*
SELECT
  r.responsibility_name,
  r.responsibility_key,
  m.menu_name,
  m.user_menu_name
FROM fnd_responsibility_vl r
JOIN fnd_menus m ON m.menu_id = r.menu_id
WHERE r.responsibility_name LIKE '%YOUR RESPONSIBILITY NAME%'
ORDER BY r.responsibility_name;
*/

-- ============================================================
-- HELPER: Find all menus (to pick the right one for Step 2)
-- ============================================================
/*
SELECT menu_name, user_menu_name
FROM fnd_menus
WHERE user_menu_name LIKE '%Admin%'
   OR user_menu_name LIKE '%Navigator%'
ORDER BY user_menu_name;
*/


SELECT menu_name
FROM fnd_menus
WHERE user_menu_name = 'MSSL_STORE_HOD_USER'
  -- OR user_menu_name LIKE 'MSSL_STORE_HOD_USER'
ORDER BY user_menu_name;



SELECT
  r.responsibility_name,
  r.responsibility_key
FROM fnd_responsibility_vl r
WHERE r.responsibility_name LIKE '%NOI_OU03%STORE%HOD%'
ORDER BY r.responsibility_name;

SELECT * FROM fnd_responsibility_vl

SELECT
  r.responsibility_name,
  r.responsibility_key,
  m.menu_name
FROM fnd_responsibility_vl r
JOIN fnd_menus m ON m.menu_id = r.menu_id
WHERE r.responsibility_name LIKE '%NOI_OU03%STORE%HOD%'
ORDER BY r.responsibility_name;