-- CRMS_SESSION_CLEANUP_PROC
CREATE OR REPLACE NONEDITIONABLE PROCEDURE "CRMS_SESSION_CLEANUP_PROC" AS
      BEGIN
        -- 1. Mark expired sessions (Absolute expiry)
        UPDATE user_sessions
           SET status = 'TOKEN_EXPIRED',
               revoked_at = SYSTIMESTAMP,
               logout_reason = 'Refresh Token Expired'
         WHERE status = 'ACTIVE'
           AND absolute_expires_at < SYSTIMESTAMP;

        -- 2. Mark idle sessions (30 minutes timeout)
        UPDATE user_sessions
           SET status = 'IDLE_TIMEOUT',
               revoked_at = SYSTIMESTAMP,
               logout_reason = 'Idle Timeout'
         WHERE status = 'ACTIVE'
           AND last_activity < SYSTIMESTAMP - INTERVAL '30' MINUTE;

        -- 3. Purge inactive sessions older than 90 days
        DELETE FROM user_sessions
         WHERE status IN ('LOGGED_OUT', 'IDLE_TIMEOUT', 'TOKEN_EXPIRED', 'REVOKED')
           AND last_activity < SYSTIMESTAMP - INTERVAL '90' DAY;

        COMMIT;
      END;
    
/
