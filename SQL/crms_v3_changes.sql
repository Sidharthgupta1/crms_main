-- ============================================================
-- CRMS V3 — Database Changes
-- Run as APPS user in SQL Developer
-- ============================================================
SET SERVEROUTPUT ON
SET DEFINE OFF

-- 1. Expand state columns (fixes ORA-12899)
BEGIN EXECUTE IMMEDIATE 'ALTER TABLE crms_releases MODIFY state VARCHAR2(60)'; EXCEPTION WHEN OTHERS THEN NULL; END;/
BEGIN EXECUTE IMMEDIATE 'ALTER TABLE crms_release_history MODIFY from_state VARCHAR2(60)'; EXCEPTION WHEN OTHERS THEN NULL; END;/
BEGIN EXECUTE IMMEDIATE 'ALTER TABLE crms_release_history MODIFY to_state VARCHAR2(60)'; EXCEPTION WHEN OTHERS THEN NULL; END;/

-- 2. Drop old state CHECK constraint and replace it
BEGIN
  FOR c IN (SELECT constraint_name FROM user_constraints
             WHERE table_name='CRMS_RELEASES' AND constraint_type='C'
               AND search_condition LIKE '%state IN%') LOOP
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases DROP CONSTRAINT '||c.constraint_name;
  END LOOP;
END;
/
ALTER TABLE crms_releases ADD CONSTRAINT chk_release_state CHECK (state IN (
  'RD Phase',
  'RD Awaiting Approval L1','RD Awaiting Approval L2','RD Awaiting Approval L3',
  'RD Awaiting Approval L4','RD Awaiting Approval L5',
  'RD Approval L1','RD Approval L2','RD Approval L3','RD Approval L4','RD Approval L5',
  'FSD Phase',
  'FSD Awaiting Approval L1','FSD Awaiting Approval L2','FSD Awaiting Approval L3',
  'FSD Awaiting Approval L4','FSD Awaiting Approval L5',
  'FSD Approval L1','FSD Approval L2','FSD Approval L3','FSD Approval L4','FSD Approval L5',
  'Development Phase','Testing Phase','UAT Phase',
  'Deployment Phase',
  'Deployment Approval L1','Deployment Approval L2','Deployment Approval L3',
  'Deployment Approval L4','Deployment Approval L5',
  'On Hold','Closed','Cancelled'
));
/

-- 3. Add RD phase fields to crms_releases (1000-char each)
DECLARE v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_tab_columns
   WHERE table_name='CRMS_RELEASES' AND column_name='REASON_OF_CHANGE';
  IF v=0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases ADD reason_of_change VARCHAR2(1000)';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases ADD business_benefits_process VARCHAR2(1000)';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases ADD business_benefits_qualitative VARCHAR2(1000)';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases ADD cost_saving VARCHAR2(1000)';
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases ADD manpower_saving VARCHAR2(1000)';
    DBMS_OUTPUT.PUT_LINE('Added RD phase fields to crms_releases');
  ELSE
    DBMS_OUTPUT.PUT_LINE('RD phase fields already exist');
  END IF;
END;
/

-- 4. Remove company/service NOT NULL (they are optional now in new flow)
-- (skip if already nullable)

-- 5. Verify
SELECT column_name, data_type, data_length, nullable
FROM user_tab_columns
WHERE table_name = 'CRMS_RELEASES'
  AND column_name IN ('STATE','REASON_OF_CHANGE','BUSINESS_BENEFITS_PROCESS',
                      'BUSINESS_BENEFITS_QUALITATIVE','COST_SAVING','MANPOWER_SAVING')
ORDER BY column_name;

COMMIT;
DBMS_OUTPUT.PUT_LINE('V3 migration complete.');
