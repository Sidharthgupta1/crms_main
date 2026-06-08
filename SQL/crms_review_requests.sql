-- ============================================================
-- CRMS: Review Requests Table
-- Run this in SQL Developer as APPS user on ebs_MSWILDEV
-- Required for the "Send for Review" feature to work
-- ============================================================
SET SERVEROUTPUT ON
SET DEFINE OFF

DECLARE
  v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name = 'CRMS_REVIEW_REQUESTS';
  IF v = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_review_requests (
        review_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_id   NUMBER NOT NULL
            CONSTRAINT fk_rr_release  REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        phase_code   VARCHAR2(20)  NOT NULL,
        sent_by      NUMBER NOT NULL
            CONSTRAINT fk_rr_sent_by  REFERENCES crms_users(user_id),
        reviewer_id  NUMBER NOT NULL
            CONSTRAINT fk_rr_reviewer REFERENCES crms_users(user_id),
        passed_to    NUMBER
            CONSTRAINT fk_rr_passed   REFERENCES crms_users(user_id),
        status       VARCHAR2(20)  DEFAULT ''Pending'' NOT NULL,
        notes        VARCHAR2(1000),
        created_at   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        updated_at   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rr_reviewer ON crms_review_requests(reviewer_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rr_release  ON crms_review_requests(release_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_rr_status   ON crms_review_requests(status)';
    DBMS_OUTPUT.PUT_LINE('SUCCESS: crms_review_requests table created.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('OK: crms_review_requests already exists.');
  END IF;
END;
/

COMMIT;

-- Verify
SELECT table_name, num_rows
  FROM user_tables
 WHERE table_name = 'CRMS_REVIEW_REQUESTS';
