DECLARE
  v_exists NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CRMS_ATTACHMENTS';
  IF v_exists = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_attachments (
        attachment_id   NUMBER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        release_id      NUMBER          NOT NULL
            CONSTRAINT fk_att_release REFERENCES crms_releases(release_id) ON DELETE CASCADE,
        file_name       VARCHAR2(500)   NOT NULL,
        file_type       VARCHAR2(200),
        file_size       NUMBER,
        file_data       CLOB            NOT NULL,
        uploaded_by     NUMBER          NOT NULL
            CONSTRAINT fk_att_user REFERENCES crms_users(user_id),
        created_at      TIMESTAMP       DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_att_release ON crms_attachments(release_id)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_att_user    ON crms_attachments(uploaded_by)';
    DBMS_OUTPUT.PUT_LINE('  CREATED : crms_attachments');
  ELSE
    DBMS_OUTPUT.PUT_LINE('  SKIPPED : crms_attachments (exists)');
  END IF;
END;
/
