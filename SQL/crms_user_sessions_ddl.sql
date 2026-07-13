-- ============================================================
-- CRMS USER_SESSIONS — Enterprise Session Management
-- Run as: APPS user on Oracle DB
-- Usage:  SQL> @crms_user_sessions_ddl.sql
-- ============================================================

SET ECHO OFF
SET SERVEROUTPUT ON
SET DEFINE OFF
WHENEVER SQLERROR CONTINUE

BEGIN
  DBMS_OUTPUT.PUT_LINE('===========================================');
  DBMS_OUTPUT.PUT_LINE('CRMS User Sessions Migration - Starting');
  DBMS_OUTPUT.PUT_LINE('User   : ' || SYS_CONTEXT('USERENV','SESSION_USER'));
  DBMS_OUTPUT.PUT_LINE('DB     : ' || SYS_CONTEXT('USERENV','DB_NAME'));
  DBMS_OUTPUT.PUT_LINE('Time   : ' || TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS'));
  DBMS_OUTPUT.PUT_LINE('===========================================');
END;
/

-- ============================================================
-- TABLE: USER_SESSIONS
-- ============================================================
DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'USER_SESSIONS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE user_sessions (
        session_id          NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        user_id             NUMBER         NOT NULL
                              CONSTRAINT fk_session_user REFERENCES crms_users(user_id),
        refresh_token_hash  VARCHAR2(64)   NOT NULL,
        device_id           VARCHAR2(64),
        device_name         VARCHAR2(200),
        browser             VARCHAR2(100),
        operating_system    VARCHAR2(100),
        ip_address          VARCHAR2(45),
        user_agent          VARCHAR2(500),
        status              VARCHAR2(10)   DEFAULT ''ACTIVE'' NOT NULL
                              CONSTRAINT chk_session_status CHECK (status IN (''ACTIVE'',''REVOKED'',''EXPIRED'')),
        created_at          TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        last_activity       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
        session_expires_at  TIMESTAMP      NOT NULL,
        revoked_at          TIMESTAMP
      )';
    DBMS_OUTPUT.PUT_LINE('  CREATED : user_sessions');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : user_sessions (exists)');
  END IF;
END;
/

-- ============================================================
-- INDEXES
-- ============================================================
DECLARE PROCEDURE safe_idx(p_sql VARCHAR2, p_name VARCHAR2) IS
BEGIN
  EXECUTE IMMEDIATE p_sql;
  DBMS_OUTPUT.PUT_LINE('  INDEX   : ' || p_name);
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE = -955 THEN DBMS_OUTPUT.PUT_LINE('  SKIPPED : ' || p_name || ' (exists)');
  ELSE RAISE; END IF;
END;
BEGIN
  safe_idx('CREATE INDEX idx_sessions_user_id ON user_sessions(user_id)', 'idx_sessions_user_id');
  safe_idx('CREATE INDEX idx_sessions_hash ON user_sessions(refresh_token_hash)', 'idx_sessions_hash');
  safe_idx('CREATE INDEX idx_sessions_status ON user_sessions(user_id, status)', 'idx_sessions_status');
  safe_idx('CREATE INDEX idx_sessions_expires ON user_sessions(session_expires_at)', 'idx_sessions_expires');
END;
/

-- ============================================================
-- PROCEDURE: Mark expired active sessions
-- ============================================================
CREATE OR REPLACE PROCEDURE crms_expire_sessions AS
  v_count NUMBER;
BEGIN
  UPDATE user_sessions
     SET status = 'EXPIRED'
   WHERE status = 'ACTIVE'
     AND session_expires_at < SYSTIMESTAMP;
  v_count := SQL%ROWCOUNT;
  COMMIT;
  IF v_count > 0 THEN
    DBMS_OUTPUT.PUT_LINE('  EXPIRED : ' || v_count || ' stale session(s)');
  END IF;
END crms_expire_sessions;
/
SHOW ERRORS PROCEDURE crms_expire_sessions;

-- ============================================================
-- PROCEDURE: Purge old revoked/expired sessions (90 days)
-- ============================================================
CREATE OR REPLACE PROCEDURE crms_purge_old_sessions(
  p_retention_days IN NUMBER DEFAULT 90
) AS
  v_count NUMBER;
BEGIN
  -- First mark any still-active expired sessions
  UPDATE user_sessions
     SET status = 'EXPIRED'
   WHERE status = 'ACTIVE'
     AND session_expires_at < SYSTIMESTAMP;
  COMMIT;

  -- Then delete revoked/expired sessions older than retention period
  DELETE FROM user_sessions
   WHERE status IN ('REVOKED', 'EXPIRED')
     AND NVL(revoked_at, session_expires_at) < SYSTIMESTAMP - p_retention_days;
  v_count := SQL%ROWCOUNT;
  COMMIT;
  IF v_count > 0 THEN
    DBMS_OUTPUT.PUT_LINE('  PURGED  : ' || v_count || ' old session(s) deleted (retention: ' || p_retention_days || ' days)');
  END IF;
END crms_purge_old_sessions;
/
SHOW ERRORS PROCEDURE crms_purge_old_sessions;

-- ============================================================
-- SCHEDULER: Auto-purge daily at 2 AM
-- ============================================================
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'CRMS_PURGE_SESSIONS',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN crms_expire_sessions; crms_purge_old_sessions(90); END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY;BYHOUR=2;BYMINUTE=0;BYSECOND=0',
    enabled         => TRUE,
    comments        => 'CRMS: Expire stale sessions and purge old revoked/expired sessions (90 day retention)'
  );
  DBMS_OUTPUT.PUT_LINE('  JOB     : CRMS_PURGE_SESSIONS created (daily at 2 AM)');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -27477 THEN
      DBMS_OUTPUT.PUT_LINE('  JOB     : CRMS_PURGE_SESSIONS already exists');
    ELSE
      DBMS_OUTPUT.PUT_LINE('  JOB     : Failed to create scheduler job - ' || SQLERRM);
    END IF;
END;
/

-- ============================================================
-- VERIFICATION
-- ============================================================
DECLARE
  v_cnt NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE(CHR(10) || '===========================================');
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM user_sessions' INTO v_cnt;
  DBMS_OUTPUT.PUT_LINE('  user_sessions : ' || v_cnt || ' rows');
  DBMS_OUTPUT.PUT_LINE('===========================================');
  DBMS_OUTPUT.PUT_LINE('Migration complete.');
  DBMS_OUTPUT.PUT_LINE('===========================================');
END;
/