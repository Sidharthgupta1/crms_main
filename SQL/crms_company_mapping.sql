-- ============================================================
-- CRMS COMPANY MAPPING — DDL
-- Run as APPS user on ebs_MSWILDEV
-- ============================================================
SET SERVEROUTPUT ON
SET DEFINE OFF

-- ── Table: CRMS_COMPANY_SERVICE_MAP ──────────────────────────────────
-- Links a Company to which Services it uses
-- e.g. MSSL uses Oracle + SAP; Motherson Innovations uses only Oracle
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name = 'CRMS_COMPANY_SERVICE_MAP';
  IF v = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_company_service_map (
        map_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        company_id    NUMBER NOT NULL
            CONSTRAINT fk_csm_company  REFERENCES crms_companies(company_id)  ON DELETE CASCADE,
        service_id    NUMBER NOT NULL
            CONSTRAINT fk_csm_service  REFERENCES crms_services(service_id)   ON DELETE CASCADE,
        created_at    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_company_service UNIQUE (company_id, service_id)
      )';
    DBMS_OUTPUT.PUT_LINE('CREATED: crms_company_service_map');
  ELSE
    DBMS_OUTPUT.PUT_LINE('EXISTS:  crms_company_service_map');
  END IF;
END;
/

-- ── Table: CRMS_COMPANY_GROUP_PHASE_MAP ──────────────────────────────
-- Links Company + Service + Phase → Assignment Group
-- e.g. MSSL + Oracle + RD Phase → MSSL-Oracle-Functional
--      MSSL + Oracle + DEV Phase → MSSL-Oracle-Technical
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tables WHERE table_name = 'CRMS_COMPANY_GROUP_PHASE_MAP';
  IF v = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE crms_company_group_phase_map (
        phase_map_id  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        company_id    NUMBER NOT NULL
            CONSTRAINT fk_cgpm_company  REFERENCES crms_companies(company_id)           ON DELETE CASCADE,
        service_id    NUMBER NOT NULL
            CONSTRAINT fk_cgpm_service  REFERENCES crms_services(service_id)            ON DELETE CASCADE,
        group_id      NUMBER NOT NULL
            CONSTRAINT fk_cgpm_group   REFERENCES crms_assignment_groups(group_id)      ON DELETE CASCADE,
        phase_code    VARCHAR2(20) NOT NULL
            CONSTRAINT chk_cgpm_phase CHECK (phase_code IN (
              ''ALL'',''RD'',''FSD'',''DEV'',''TESTING'',''UAT'',''DEPLOYMENT'',''DBA_DEPLOYMENT'',''OBSERVATION''
            )),
        created_at    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT uq_company_service_group_phase UNIQUE (company_id, service_id, group_id, phase_code)
      )';
    DBMS_OUTPUT.PUT_LINE('CREATED: crms_company_group_phase_map');
    EXECUTE IMMEDIATE 'CREATE INDEX idx_cgpm_co_svc ON crms_company_group_phase_map(company_id, service_id)';
  ELSE
    DBMS_OUTPUT.PUT_LINE('EXISTS:  crms_company_group_phase_map');
  END IF;
END;
/

-- ── View: vw_company_group_phase ─────────────────────────────────────
-- Joins all names for easy frontend consumption
CREATE OR REPLACE VIEW vw_company_group_phase AS
SELECT
  m.phase_map_id,
  m.company_id,
  c.company_name,
  m.service_id,
  s.service_name,
  m.group_id,
  g.group_name,
  m.phase_code
FROM crms_company_group_phase_map m
JOIN crms_companies         c ON c.company_id  = m.company_id
JOIN crms_services          s ON s.service_id  = m.service_id
JOIN crms_assignment_groups g ON g.group_id    = m.group_id
/

COMMIT;
DBMS_OUTPUT.PUT_LINE('Company Mapping DDL complete.');
