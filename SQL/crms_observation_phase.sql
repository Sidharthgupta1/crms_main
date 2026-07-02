-- ============================================================
-- CRMS — Add Observation Phase to release workflow
-- Run in SQL Developer as APPS user
-- ============================================================

SET SERVEROUTPUT ON

BEGIN
  FOR c IN (SELECT constraint_name FROM user_constraints
             WHERE table_name='CRMS_RELEASES' AND constraint_type='C'
               AND search_condition LIKE '%state IN%') LOOP
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases DROP CONSTRAINT '||c.constraint_name;
    DBMS_OUTPUT.PUT_LINE('Dropped constraint: '||c.constraint_name);
  END LOOP;
END;
/

ALTER TABLE crms_releases ADD CONSTRAINT chk_release_state CHECK (state IN (
  'Draft',
  'Draft Awaiting Approval L1','Draft Awaiting Approval L2','Draft Awaiting Approval L3',
  'Draft Awaiting Approval L4','Draft Awaiting Approval L5',
  'RD Phase',
  'RD Awaiting Approval L1','RD Awaiting Approval L2','RD Awaiting Approval L3',
  'RD Awaiting Approval L4','RD Awaiting Approval L5',
  'FSD Phase',
  'FSD Awaiting Approval L1','FSD Awaiting Approval L2','FSD Awaiting Approval L3',
  'FSD Awaiting Approval L4','FSD Awaiting Approval L5',
  'Development Phase',
  'Testing Phase',
  'UAT Phase',
  'Deployment Phase',
  'Deployment Approval L1','Deployment Approval L2','Deployment Approval L3',
  'Deployment Approval L4','Deployment Approval L5',
  'Deployment Awaiting Approval L1','Deployment Awaiting Approval L2',
  'Deployment Awaiting Approval L3','Deployment Awaiting Approval L4',
  'Deployment Awaiting Approval L5',
  'Observation Phase',
  'On Hold','Closed','Cancelled'
));
/

COMMIT;
