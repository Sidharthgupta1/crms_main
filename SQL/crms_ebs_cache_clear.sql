-- ============================================================
-- CRMS — Clear EBS Cache after Menu Registration
-- Run as APPS user — REQUIRED after any menu change
-- ============================================================
SET DEFINE OFF
SET SERVEROUTPUT ON

-- Method 1: Compile Security (most reliable)
BEGIN
  DBMS_OUTPUT.PUT_LINE('Clearing EBS menu cache...');

  -- Recompile all grants and functions
  FND_FUNCTION.COMPILE_ALL_ENABLED_FUNCTIONS;
  DBMS_OUTPUT.PUT_LINE('  FND_FUNCTION compiled.');

EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  Warning: ' || SQLERRM);
END;
/
COMMIT;

-- Method 2: Touch the menu timestamp so EBS knows to reload
UPDATE fnd_menus
   SET last_update_date = SYSDATE,
       last_updated_by  = 1
 WHERE menu_id IN (
   SELECT DISTINCT me.menu_id
   FROM fnd_menu_entries me
   JOIN fnd_form_functions f ON f.function_id = me.function_id
   WHERE f.function_name = 'CRMS_MAIN'
);

COMMIT;
DBMS_OUTPUT.PUT_LINE('Cache cleared. Log out of EBS and log back in to see CRMS in the menu.');

-- Verify CRMS function is registered correctly
PROMPT
PROMPT === CRMS Function Verification ===
SELECT
  f.function_name,
  f.user_function_name,
  f.type,
  SUBSTR(f.web_html_call, 1, 80) AS html_call_preview
FROM fnd_form_functions f
WHERE f.function_name = 'CRMS_MAIN';

PROMPT
PROMPT === Menus containing CRMS ===
SELECT
  m.menu_name,
  m.user_menu_name,
  me.sequence_number,
  me.prompt
FROM fnd_menu_entries me
JOIN fnd_menus m ON m.menu_id = me.menu_id
JOIN fnd_form_functions f ON f.function_id = me.function_id
WHERE f.function_name = 'CRMS_MAIN'
ORDER BY m.menu_name;

PROMPT
PROMPT === Responsibilities that can see CRMS ===
SELECT DISTINCT
  r.responsibility_name,
  r.responsibility_key
FROM fnd_responsibility r
JOIN fnd_menus m ON m.menu_id = r.menu_id
WHERE m.menu_id IN (
  SELECT me.menu_id
  FROM fnd_menu_entries me
  JOIN fnd_form_functions f ON f.function_id = me.function_id
  WHERE f.function_name = 'CRMS_MAIN'
)
ORDER BY r.responsibility_name;
