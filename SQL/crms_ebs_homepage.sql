-- ============================================================
-- OPTION 2: Add CRMS Link to EBS Home Page for ALL Users
-- Run as APPS user — No System Administrator menu needed
-- ============================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- ============================================================
-- METHOD A: Add as a Global Announcement on Home Page
-- ============================================================
DECLARE
  l_exists  NUMBER;
  l_crms_url VARCHAR2(500) := 'http://10.240.182.66:3000';
BEGIN
  -- Check FND_LOBS for existing entry
  SELECT COUNT(*) INTO l_exists
    FROM fnd_documents
   WHERE URL LIKE '%CR Management System%';

  DBMS_OUTPUT.PUT_LINE('=== Adding CRMS to EBS Home Page ===');
  DBMS_OUTPUT.PUT_LINE('CRMS URL: ' || l_crms_url);
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('Choose one of the methods below:');
  DBMS_OUTPUT.PUT_LINE('');
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

-- ============================================================
-- METHOD B: Add via ICX_PARAMETERS (Global Home Page Links)
-- Works in most EBS R12 installations
-- ============================================================
DECLARE
  l_crms_url  VARCHAR2(500) := 'http://10.240.182.66:3000';
  -- Change above to your actual CRMS server

  l_exists    NUMBER;
  l_param_id  NUMBER;
BEGIN
  -- Check if ICX_PORTLET_CUSTOMIZATIONS table exists
  SELECT COUNT(*) INTO l_exists
    FROM user_tables
   WHERE table_name = 'ICX_PORTLET_CUSTOMIZATIONS';

  IF l_exists > 0 THEN
    DBMS_OUTPUT.PUT_LINE('Adding via ICX_PORTLET_CUSTOMIZATIONS...');
    -- Add as a portlet link on the home page
    MERGE INTO icx_portlet_customizations ipc
    USING DUAL
    ON (ipc.url = l_crms_url)
    WHEN NOT MATCHED THEN
    INSERT (
      portlet_customization_id,
      portlet_type,
      page_id,
      region_id,
      display_name,
      url,
      active_flag,
      created_by,
      creation_date,
      last_updated_by,
      last_update_date,
      last_update_login
    ) VALUES (
      icx_portlet_customizations_s.NEXTVAL,
      'URL',
      'HOME',
      'QUICKLINKS',
      'CR Management System',
      l_crms_url,
      'Y',
      1, SYSDATE, 1, SYSDATE, 0
    );
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('SUCCESS: Added to Home Page Quick Links');
  ELSE
    DBMS_OUTPUT.PUT_LINE('ICX_PORTLET_CUSTOMIZATIONS not found — using alternate method');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Method B: ' || SQLERRM);
END;
/

-- ============================================================
-- METHOD C: FND_PROFILE — Set a site-level profile to show link
-- This works in ALL EBS R12 versions
-- ============================================================
DECLARE
  l_crms_url VARCHAR2(500) := 'http://10.240.182.66:3000';
BEGIN
  -- Create a user-accessible URL via FND_PROFILE
  FND_PROFILE.SAVE(
    x_name         => 'CRMS_URL',
    x_value        => l_crms_url,
    x_level_name   => 'SITE',
    x_level_value  => NULL
  );
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Profile CRMS_URL set to: ' || l_crms_url);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Profile method: ' || SQLERRM);
END;
/

-- ============================================================
-- METHOD D: Add a Bookmarks entry that appears in all sessions
-- This is the most reliable method across EBS versions
-- ============================================================
DECLARE
  l_crms_url VARCHAR2(500) := 'http://10.240.182.66:3000';
  l_exists   NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_exists
    FROM fnd_bookmarks
   WHERE bookmark_url LIKE '%' || 'YOUR-SERVER' || '%';

  IF l_exists = 0 THEN
    INSERT INTO fnd_bookmarks (
      bookmark_id,
      bookmark_name,
      bookmark_url,
      description,
      active_flag,
      object_type,
      created_by,
      creation_date,
      last_updated_by,
      last_update_date,
      last_update_login
    ) VALUES (
      fnd_bookmarks_s.NEXTVAL,
      'CR Management System',
      l_crms_url,
      'Motherson Change Request Management System',
      'Y',
      'URL',
      1, SYSDATE, 1, SYSDATE, 0
    );
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Added to FND Bookmarks');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Already in FND Bookmarks');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Bookmarks: ' || SQLERRM);
END;
/

-- ============================================================
-- VERIFICATION
-- ============================================================
PROMPT
PROMPT === What was added ===
SELECT 'Profile' AS method, profile_option_value AS value
  FROM fnd_profile_option_values v
  JOIN fnd_profile_options o ON o.profile_option_id = v.profile_option_id
 WHERE o.profile_option_name = 'CRMS_URL'
UNION ALL
SELECT 'Bookmark', bookmark_url
  FROM fnd_bookmarks
 WHERE bookmark_name LIKE '%CR Management%';

PROMPT
PROMPT ============================================================
PROMPT Next Steps:
PROMPT 1. Log out of EBS and log back in
PROMPT 2. Look for "CR Management System" in:
PROMPT    - Home Page Quick Links section  
PROMPT    - Navigator -> Bookmarks
PROMPT    - Top navigation bar (in some EBS versions)
PROMPT ============================================================
