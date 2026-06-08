-- ============================================================
-- CRMS Approval Groups — Company/Service/Module → Group mapping
-- for RD (and future) phase approvals
-- Run as APPS user on ebs_MSWILDEV
-- ============================================================
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name='CRMS_APPROVAL_GROUPS';
  IF v=0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_approval_groups (
        ag_map_id    NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        company_name VARCHAR2(200),
        service_name VARCHAR2(200),
        module_id    NUMBER
                       CONSTRAINT fk_apgrp_mod REFERENCES crms_modules(module_id) ON DELETE CASCADE,
        group_id     NUMBER         NOT NULL
                       CONSTRAINT fk_apgrp_grp REFERENCES crms_assignment_groups(group_id) ON DELETE CASCADE,
        phase_code   VARCHAR2(20)   DEFAULT ''RD'' NOT NULL,
        created_at   TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
      )';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_apgrp_company ON crms_approval_groups(company_name)';
    EXECUTE IMMEDIATE 'CREATE INDEX idx_apgrp_module  ON crms_approval_groups(module_id)';
    DBMS_OUTPUT.PUT_LINE('CREATED: crms_approval_groups');
  ELSE
    DBMS_OUTPUT.PUT_LINE('EXISTS:  crms_approval_groups');
  END IF;
END;
/
COMMIT;
