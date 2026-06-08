-- ============================================================
-- CRMS EBS Diagnostic — Run ALL queries and share the output
-- Run as APPS user in Toad / SQL Developer
-- ============================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

PROMPT ============================================================
PROMPT DIAGNOSTIC 1: Is the CRMS function created?
PROMPT ============================================================
SELECT
  function_id,
  function_name,
  type,
  SUBSTR(web_html_call, 1, 100) AS html_call
FROM fnd_form_functions
WHERE function_name = 'CR_MANEGMENT';

PROMPT
PROMPT ============================================================
PROMPT DIAGNOSTIC 2: Which menu(s) contain the CRMS function?
PROMPT ============================================================
SELECT
  m.menu_id,
  m.menu_name,
  m.user_menu_name,
  me.sequence_number,
  me.prompt,
  me.grant_flag
FROM fnd_menu_entries me
JOIN fnd_menus m ON m.menu_id = me.menu_id
JOIN fnd_form_functions f ON f.function_id = me.function_id
WHERE f.function_name = 'CR_MANEGMENT';

PROMPT
PROMPT ============================================================
PROMPT DIAGNOSTIC 3: Which responsibilities use those menus?
PROMPT ============================================================
SELECT
  r.responsibility_id,
  r.responsibility_name,
  r.responsibility_key,
  m.menu_name,
  m.user_menu_name,
  r.start_date,
  r.end_date,
  NVL(TO_CHAR(r.end_date,'DD-MON-YYYY'), 'ACTIVE') AS status
FROM fnd_responsibility_vl r
JOIN fnd_menus m ON m.menu_id = r.menu_id
WHERE m.menu_id IN (
  SELECT DISTINCT me.menu_id
  FROM fnd_menu_entries me
  JOIN fnd_form_functions f ON f.function_id = me.function_id
  WHERE f.function_name = 'CR_MANEGMENT'
)
ORDER BY r.responsibility_name;

PROMPT
PROMPT ============================================================
PROMPT DIAGNOSTIC 4: Is CRMS excluded anywhere? (security exclusions)
PROMPT ============================================================
SELECT
  r.responsibility_name,
  re.action,
  re.type,
  f.function_name,
  f.user_function_name
FROM fnd_resp_functions re
JOIN fnd_responsibility_vl r ON r.responsibility_id = re.responsibility_id
LEFT JOIN fnd_form_functions f ON f.function_id = re.action_id AND re.type = 'F'
WHERE UPPER(f.function_name) LIKE '%CR_MANEGMENT%'
   OR re.responsibility_id IN (
     SELECT r2.responsibility_id
     FROM fnd_responsibility r2
     JOIN fnd_menus m ON m.menu_id = r2.menu_id
     WHERE m.menu_id IN (
       SELECT DISTINCT me.menu_id
       FROM fnd_menu_entries me
       JOIN fnd_form_functions f2 ON f2.function_id = me.function_id
       WHERE f2.function_name = 'CR_MANEGMENT'
     )
   );

PROMPT
PROMPT ============================================================
PROMPT DIAGNOSTIC 5: Which menu is attached to YOUR responsibility?
PROMPT (Change the name below to match what you log in with)
PROMPT ============================================================
SELECT
  r.responsibility_name,
  r.responsibility_key,
  r.menu_id,
  m.menu_name,
  m.user_menu_name
FROM fnd_responsibility_vl r
JOIN fnd_menus m ON m.menu_id = r.menu_id
WHERE UPPER(r.responsibility_name) LIKE '%SYSTEM ADMINISTRATOR%'
   OR UPPER(r.responsibility_name) LIKE '%MSSL%'
   OR UPPER(r.responsibility_name) LIKE '%IT%'
   OR UPPER(r.responsibility_name) LIKE '%ADMIN%'
ORDER BY r.responsibility_name;

PROMPT
PROMPT ============================================================
PROMPT DIAGNOSTIC 6: Check if CRMS is in the Navigator hierarchy
PROMPT (recursive — shows full menu path to CRMS)
PROMPT ============================================================
SELECT
  LEVEL,
  LPAD(' ', (LEVEL-1)*3) || m.menu_name AS menu_hierarchy,
  me.prompt,
  f.function_name
FROM fnd_menu_entries me
JOIN fnd_menus m ON m.menu_id = me.menu_id
LEFT JOIN fnd_form_functions f ON f.function_id = me.function_id
WHERE f.function_name = 'CR_MANEGMENT'
   OR UPPER(me.prompt) LIKE '%CR_MANEGMENT%'
   OR UPPER(me.prompt) LIKE '%CR_MANEGMENT%';

PROMPT
PROMPT ============================================================
PROMPT DIAGNOSTIC 7: FND_FUNCTION_SECURITY — is CRMS accessible?
PROMPT ============================================================
SELECT
  ffs.function_id,
  ffs.responsibility_id,
  r.responsibility_name,
  f.function_name,
  f.user_function_name
FROM fnd_compiled_menu_functions ffs
JOIN fnd_form_functions f ON f.function_id = ffs.function_id
JOIN fnd_responsibility_vl r ON r.responsibility_id = ffs.responsibility_id
WHERE f.function_name = 'CR_MANEGMENT'
ORDER BY r.responsibility_name;

PROMPT
PROMPT ============================================================
PROMPT DIAGNOSTIC 8: Grant flag check
PROMPT ============================================================
SELECT
  me.menu_id,
  m.menu_name,
  me.sequence_number,
  me.prompt,
  me.grant_flag,
  f.function_name,
  f.type AS function_type
FROM fnd_menu_entries me
JOIN fnd_menus m ON m.menu_id = me.menu_id
JOIN fnd_form_functions f ON f.function_id = me.function_id
WHERE f.function_name = 'CR_MANEGMENT';

PROMPT
PROMPT ============================================================
PROMPT Share ALL of the above output with your administrator.
PROMPT The key diagnostics are 2, 3, 5, and 7.
PROMPT ============================================================
