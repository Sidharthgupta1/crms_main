-- ============================================================
-- CRMS FND_USER SSO — Complete Database Setup
-- Run as APPS user in Toad / SQL Developer on ebs_MSWILDEV
-- ============================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

PROMPT ============================================================
PROMPT STEP 1: Add fnd_user_name column to crms_users
PROMPT ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns
   WHERE table_name='CRMS_USERS' AND column_name='FND_USER_NAME';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_users ADD fnd_user_name VARCHAR2(100)';
    EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX idx_crms_users_fnd ON crms_users(UPPER(fnd_user_name))';
    DBMS_OUTPUT.PUT_LINE('OK: fnd_user_name column added to crms_users');
  ELSE
    DBMS_OUTPUT.PUT_LINE('OK: fnd_user_name already exists');
  END IF;
END;
/

PROMPT ============================================================
PROMPT STEP 2: Create crms_sso_tokens table (one-time login tokens)
PROMPT ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_SSO_TOKENS';
  IF v=0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_sso_tokens (
        token_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        token       VARCHAR2(64)  NOT NULL UNIQUE,
        fnd_user_id NUMBER        NOT NULL,
        crms_user_id NUMBER       NOT NULL
            CONSTRAINT fk_sso_crms_user REFERENCES crms_users(user_id),
        created_at  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        expires_at  TIMESTAMP NOT NULL,
        used        NUMBER(1) DEFAULT 0 NOT NULL,
        used_at     TIMESTAMP
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_sso_token  ON crms_sso_tokens(token)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_sso_expires ON crms_sso_tokens(expires_at)';
    DBMS_OUTPUT.PUT_LINE('OK: crms_sso_tokens table created');
  ELSE
    DBMS_OUTPUT.PUT_LINE('OK: crms_sso_tokens already exists');
  END IF;
END;
/

PROMPT ============================================================
PROMPT STEP 3: Map existing CRMS users to FND_USER accounts
PROMPT Edit the values below to match your actual Oracle usernames
PROMPT To find Oracle usernames: SELECT user_name FROM fnd_user WHERE ROWNUM < 30;
PROMPT ============================================================

-- Map each CRMS user to their Oracle EBS login username
-- The fnd_user_name is exactly what they type at the EBS login screen
UPDATE crms_users SET fnd_user_name = 'SANDEEP.GUPTA'  WHERE initials = 'SG';
UPDATE crms_users SET fnd_user_name = 'ROHIT.KUMAR'    WHERE initials = 'RK';
UPDATE crms_users SET fnd_user_name = 'PRIYA.MEHTA'    WHERE initials = 'PM';
UPDATE crms_users SET fnd_user_name = 'AMIT.VERMA'     WHERE initials = 'AV';
-- Add more mappings as needed:
-- UPDATE crms_users SET fnd_user_name = 'ORACLE.USERNAME' WHERE initials = 'XX';
COMMIT;

PROMPT ============================================================
PROMPT STEP 4: Create the PL/SQL package for EBS menu integration
PROMPT ============================================================

CREATE OR REPLACE PACKAGE crms_sso_pkg AS
  -- Call this from EBS menu function / OAF page / custom form
  -- It generates the SSO URL and redirects the browser to CRMS
  PROCEDURE open_crms(
    p_crms_url IN VARCHAR2 DEFAULT 'http://YOUR-CRMS-SERVER:3000'
  );

  -- Returns the SSO URL without redirecting (for testing)
  FUNCTION get_sso_url(
    p_crms_url IN VARCHAR2 DEFAULT 'http://YOUR-CRMS-SERVER:3000'
  ) RETURN VARCHAR2;

  -- Test: show what URL would be generated for current user
  PROCEDURE test_sso(
    p_crms_url IN VARCHAR2 DEFAULT 'http://YOUR-CRMS-SERVER:3000'
  );
END crms_sso_pkg;
/
SHOW ERRORS PACKAGE crms_sso_pkg;

CREATE OR REPLACE PACKAGE BODY crms_sso_pkg AS

  -- ── Get a one-time SSO token from CRMS backend ──────────────────────
  -- CRMS backend is on the same network, call its REST API
  FUNCTION get_sso_url(
    p_crms_url IN VARCHAR2 DEFAULT 'http://YOUR-CRMS-SERVER:3000'
  ) RETURN VARCHAR2
  IS
    l_fnd_username  VARCHAR2(100);
    l_token         VARCHAR2(64);
    l_request       UTL_HTTP.REQ;
    l_response      UTL_HTTP.RESP;
    l_buffer        VARCHAR2(32767);
    l_full_response VARCHAR2(32767) := '';
    l_token_start   NUMBER;
    l_token_end     NUMBER;
    l_api_url       VARCHAR2(500);
    l_body          VARCHAR2(500);
  BEGIN
    -- Get current Oracle EBS username
    l_fnd_username := UPPER(FND_GLOBAL.USER_NAME);

    IF l_fnd_username IS NULL OR l_fnd_username = 'GUEST' THEN
      RETURN p_crms_url || '/?error=no_oracle_session';
    END IF;

    -- Call CRMS backend API to get one-time token
    -- POST /api/v1/auth/fnd-token  { fndUserName: "JOHN.SMITH" }
    l_api_url := p_crms_url || '/api/v1/auth/fnd-token';
    l_body    := '{"fndUserName":"' || l_fnd_username || '"}';

    BEGIN
      l_request := UTL_HTTP.BEGIN_REQUEST(l_api_url, 'POST', 'HTTP/1.1');
      UTL_HTTP.SET_HEADER(l_request, 'Content-Type',   'application/json');
      UTL_HTTP.SET_HEADER(l_request, 'Content-Length', LENGTH(l_body));
      UTL_HTTP.SET_HEADER(l_request, 'Accept',         'application/json');
      UTL_HTTP.WRITE_TEXT(l_request, l_body);

      l_response := UTL_HTTP.GET_RESPONSE(l_request);

      -- Read response
      BEGIN
        LOOP
          UTL_HTTP.READ_LINE(l_response, l_buffer, FALSE);
          l_full_response := l_full_response || l_buffer;
        END LOOP;
      EXCEPTION
        WHEN UTL_HTTP.END_OF_BODY THEN NULL;
      END;
      UTL_HTTP.END_RESPONSE(l_response);

      -- Parse token from JSON response: {"token":"abc123..."}
      l_token_start := INSTR(l_full_response, '"token":"') + 9;
      l_token_end   := INSTR(l_full_response, '"', l_token_start);

      IF l_token_start > 9 AND l_token_end > l_token_start THEN
        l_token := SUBSTR(l_full_response, l_token_start, l_token_end - l_token_start);
        RETURN p_crms_url || '/api/v1/auth/fnd-sso?token=' || l_token;
      ELSE
        -- API returned error — redirect to CRMS with error message
        RETURN p_crms_url || '/?sso_error=' || UTL_URL.ESCAPE(l_full_response, FALSE);
      END IF;

    EXCEPTION
      WHEN OTHERS THEN
        RETURN p_crms_url || '/?sso_error=' || UTL_URL.ESCAPE(SQLERRM, FALSE);
    END;

  END get_sso_url;

  -- ── Redirect browser to CRMS with SSO ────────────────────────────────
  PROCEDURE open_crms(
    p_crms_url IN VARCHAR2 DEFAULT 'http://YOUR-CRMS-SERVER:3000'
  ) IS
    l_url VARCHAR2(1000);
  BEGIN
    l_url := get_sso_url(p_crms_url);
    OWA_UTIL.REDIRECT_URL(l_url);
  END open_crms;

  -- ── Test — prints the URL to DBMS Output ─────────────────────────────
  PROCEDURE test_sso(
    p_crms_url IN VARCHAR2 DEFAULT 'http://YOUR-CRMS-SERVER:3000'
  ) IS
    l_url VARCHAR2(1000);
  BEGIN
    DBMS_OUTPUT.PUT_LINE('Current Oracle User: ' || FND_GLOBAL.USER_NAME);
    l_url := get_sso_url(p_crms_url);
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Generated SSO URL:');
    DBMS_OUTPUT.PUT_LINE(l_url);
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Open this URL in a browser to test auto-login.');
  END test_sso;

END crms_sso_pkg;
/
SHOW ERRORS PACKAGE BODY crms_sso_pkg;

PROMPT ============================================================
PROMPT STEP 5: Allow UTL_HTTP to call CRMS server
PROMPT (Run as SYSDBA if APPS doesn't have network access)
PROMPT ============================================================
-- Run as SYSDBA:
-- EXEC DBMS_NETWORK_ACL_ADMIN.CREATE_ACL('crms_acl.xml','CRMS Backend','APPS',TRUE,'connect');
-- EXEC DBMS_NETWORK_ACL_ADMIN.ADD_PRIVILEGE('crms_acl.xml','APPS',TRUE,'resolve');
-- EXEC DBMS_NETWORK_ACL_ADMIN.ASSIGN_ACL('crms_acl.xml','YOUR-CRMS-SERVER-IP');
-- COMMIT;

PROMPT ============================================================
PROMPT STEP 6: Verify mappings are correct
PROMPT ============================================================
SELECT
  cu.initials,
  cu.full_name      AS crms_name,
  cu.fnd_user_name  AS oracle_username,
  fu.user_id        AS fnd_user_id,
  fu.email_address  AS email,
  CASE WHEN fu.user_id IS NOT NULL THEN 'LINKED' ELSE 'NOT LINKED' END AS status
FROM crms_users cu
LEFT JOIN fnd_user fu
  ON UPPER(fu.user_name) = UPPER(cu.fnd_user_name)
 AND NVL(fu.end_date, SYSDATE+1) > SYSDATE
ORDER BY cu.initials;

PROMPT
PROMPT ============================================================
PROMPT STEP 7: Register in Oracle EBS
PROMPT ============================================================
PROMPT
PROMPT In System Administrator:
PROMPT   Application > Function > Create new:
PROMPT     Function Name  : CRMS_MAIN
PROMPT     User Function  : CR Management System
PROMPT     Type           : SSWA JSP Function
PROMPT     Web HTML Call  :
PROMPT     javascript:void(crms_sso_pkg.open_crms('http://YOUR-CRMS-SERVER:3000'))
PROMPT
PROMPT OR use the simpler URL-only approach:
PROMPT     HTML Call: http://YOUR-CRMS-SERVER:3000/api/v1/auth/fnd-sso?token=AUTO
PROMPT     (This requires Oracle Apache to inject username header)
PROMPT
PROMPT Then: Application > Menu > add CRMS_MAIN to your menu
PROMPT Then: Compile Security (Utilities > Compile Security)
PROMPT Then: Log out and log back in
PROMPT ============================================================
