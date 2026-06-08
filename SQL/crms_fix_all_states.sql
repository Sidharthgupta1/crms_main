-- ============================================================
-- CRMS FIX — Run in SQL Developer as APPS user
-- Fixes ORA-12899 on crms_releases.state and crms_release_history
-- 'Deployment Awaiting Approval L1' = 31 chars > VARCHAR2(30)
-- ============================================================

SET SERVEROUTPUT ON

-- 1. crms_releases.state column + CHECK constraint
BEGIN
  -- Drop the existing CHECK constraint first
  FOR c IN (SELECT constraint_name FROM user_constraints
             WHERE table_name='CRMS_RELEASES' AND constraint_type='C'
               AND search_condition LIKE '%state IN%') LOOP
    EXECUTE IMMEDIATE 'ALTER TABLE crms_releases DROP CONSTRAINT '||c.constraint_name;
    DBMS_OUTPUT.PUT_LINE('Dropped constraint: '||c.constraint_name);
  END LOOP;
END;
/

-- Expand the column
ALTER TABLE crms_releases MODIFY state VARCHAR2(60) NOT NULL;
/

-- Re-add the CHECK constraint with VARCHAR2(60)-safe values
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
  'Deployment Awaiting Approval L1','Deployment Awaiting Approval L2',
  'Deployment Awaiting Approval L3','Deployment Awaiting Approval L4',
  'Deployment Awaiting Approval L5',
  'On Hold','Closed','Cancelled'
));
/

-- 2. crms_release_history from_state / to_state
ALTER TABLE crms_release_history MODIFY from_state VARCHAR2(60);
ALTER TABLE crms_release_history MODIFY to_state   VARCHAR2(60) NOT NULL;
/

-- 3. Verify
SELECT table_name, column_name, data_length
FROM   user_tab_columns
WHERE  table_name IN ('CRMS_RELEASES','CRMS_RELEASE_HISTORY')
  AND  column_name IN ('STATE','FROM_STATE','TO_STATE')
ORDER  BY table_name, column_name;

COMMIT;
