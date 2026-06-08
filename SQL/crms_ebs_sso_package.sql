-- ============================================================
-- CRMS EBS SSO — PL/SQL Package
-- Run as APPS user in SQL Developer on ebs_MSWILDEV
--
-- IMPORTANT: SET DEFINE OFF disables & as substitution variable
-- so SQL Developer does NOT prompt for &ts, &sig, &redirect
-- ============================================================

SET DEFINE OFF
SET SERVEROUTPUT ON

-- ============================================================
-- PACKAGE SPEC
-- ============================================================
CREATE OR REPLACE PACKAGE crms_sso_pkg AS

  -- Main procedure: called from OAF page or custom EBS function
  -- Generates signed URL and redirects browser to CRMS
  PROCEDURE redirect_to_crms(
    p_crms_url  IN VARCHAR2 DEFAULT 'http://10.240.182.45:3000'
  );

  -- Utility: generate the signed URL without redirecting
  -- Useful for testing or embedding in OAF managed beans
  FUNCTION get_crms_url(
    p_crms_url  IN VARCHAR2 DEFAULT 'http://10.240.182.45:3000'
  ) RETURN VARCHAR2;

END crms_sso_pkg;
/
SHOW ERRORS PACKAGE crms_sso_pkg;

-- ============================================================
-- PACKAGE BODY
-- ============================================================
CREATE OR REPLACE PACKAGE BODY crms_sso_pkg AS

  -- Shared secret — must exactly match SSO_SHARED_SECRET in crms-backend/.env
  c_secret  CONSTANT VARCHAR2(200) := 'motherson_ebs_sso_secret_2025';

  -- ── FUNCTION: build the signed CRMS URL ──────────────────────────
  FUNCTION get_crms_url(
    p_crms_url IN VARCHAR2 DEFAULT 'http://10.240.182.45:3000'
  ) RETURN VARCHAR2
  IS
    l_username  VARCHAR2(100);
    l_timestamp NUMBER;
    l_payload   VARCHAR2(500);
    l_sig       VARCHAR2(64);
    l_url       VARCHAR2(2000);
  BEGIN
    -- 1. Get the Oracle EBS username of the currently logged-in user
    l_username := UPPER(FND_GLOBAL.USER_NAME);

    -- 2. Unix timestamp = seconds since 1970-01-01
    l_timestamp := TRUNC(
      (SYSDATE - TO_DATE('1970-01-01', 'YYYY-MM-DD')) * 86400
    );

    -- 3. Payload to sign: "USERNAME:TIMESTAMP"
    l_payload := l_username || ':' || TO_CHAR(l_timestamp);

    -- 4. HMAC-SHA256 signature using DBMS_CRYPTO
    l_sig := LOWER(RAWTOHEX(
      DBMS_CRYPTO.MAC(
        src => UTL_RAW.CAST_TO_RAW(l_payload),
        typ => DBMS_CRYPTO.HMAC_SH256,
        key => UTL_RAW.CAST_TO_RAW(c_secret)
      )
    ));

    -- 5. Build the full redirect URL
    --    Note: concatenate each piece separately — no & in string literals
    l_url := p_crms_url
      || '/api/v1/auth/ebs-sso-redirect'
      || '?username=' || UTL_URL.ESCAPE(l_username, FALSE)
      || CHR(38) || 'ts='  || TO_CHAR(l_timestamp)
      || CHR(38) || 'sig=' || l_sig
      || CHR(38) || 'redirect=/';

    RETURN l_url;

  EXCEPTION
    WHEN OTHERS THEN
      -- Return a safe fallback URL on any error
      RETURN p_crms_url || '/?sso_error=' || UTL_URL.ESCAPE(SQLERRM, FALSE);
  END get_crms_url;

  -- ── PROCEDURE: redirect the browser to CRMS ──────────────────────
  PROCEDURE redirect_to_crms(
    p_crms_url IN VARCHAR2 DEFAULT 'http://10.240.182.45:3000'
  )
  IS
    l_url VARCHAR2(2000);
  BEGIN
    l_url := get_crms_url(p_crms_url);
    OWA_UTIL.REDIRECT_URL(l_url);
  END redirect_to_crms;

END crms_sso_pkg;
/
SHOW ERRORS PACKAGE BODY crms_sso_pkg;

-- ============================================================
-- QUICK TEST — run this after creating the package
-- Prints the URL that would be generated for the current user
-- ============================================================
SET DEFINE OFF
DECLARE
  l_test_url VARCHAR2(2000);
BEGIN
  -- Replace with your actual CRMS server address
  l_test_url := crms_sso_pkg.get_crms_url('http://10.240.182.45:3000');
  DBMS_OUTPUT.PUT_LINE('Generated SSO URL:');
  DBMS_OUTPUT.PUT_LINE(l_test_url);
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('Open this URL in a browser to test SSO login.');
END;
/

-- ============================================================
-- HOW TO CALL FROM AN OAF PAGE OR CUSTOM EBS MENU FUNCTION
-- ============================================================
-- Option A: From a PL/SQL procedure called by a custom EBS form:
--
--   crms_sso_pkg.redirect_to_crms('http://10.240.182.45:3000');
--
-- Option B: From an OAF Managed Bean (Java):
--
--   String sql = "BEGIN :1 := crms_sso_pkg.get_crms_url(:2); END;";
--   OADBTransaction txn = pageContext.getApplicationModule(webBean).getOADBTransaction();
--   CallableStatement cs = txn.createCallableStatement(sql, 0);
--   cs.registerOutParameter(1, Types.VARCHAR);
--   cs.setString(2, "http://10.240.182.45:3000");
--   cs.execute();
--   String crmsUrl = cs.getString(1);
--   pageContext.putParameter("ora_flex_cb", crmsUrl); // or use javascript redirect
--
-- Option C: As a Direct EBS Function URL (no PL/SQL needed):
--   Register in System Administrator > Application > Function
--   Type: JSP, HTML call:
--   javascript:window.open('http://10.240.182.45:3000/api/v1/auth/ebs-sso-redirect?username='
--     +apps.fnd_web_sec.get_guest_username()+'&ts='+new Date().getTime(),'_blank')
--   (Note: Option C does NOT have HMAC — use only in internal networks)
