-- ============================================================
-- CRMS Task List — De-dupe + Uniqueness Guard
-- Run as APPS user on ebs_MSWILDEV, AFTER crms_task_list_v2_ddl.sql
--
-- Background: ensureTaskListRow() in taskListController.js does a
-- SELECT-then-INSERT/UPDATE that is not atomic. Two concurrent calls for
-- the same cr_number (e.g. CR creation and an RD sub-task upsert firing
-- close together) could both see "no row" and both INSERT, producing
-- duplicate crms_task_list rows for one CR. That made the manually-typed
-- Delay Reason / Comments / Tracker Comments fields appear to randomly
-- revert, since whichever duplicate a later query happened to pick would
-- "win" nondeterministically.
--
-- This script:
--   1. De-duplicates existing rows (keeps the most recently updated row
--      per cr_number, soft-deletes the rest via is_deleted=1)
--   2. Adds a unique index so it can never happen again — a second
--      concurrent INSERT for the same cr_number will now fail with
--      ORA-00001, which the application code catches and falls back to
--      an UPDATE instead of creating a duplicate.
-- ============================================================
SET SERVEROUTPUT ON
SET DEFINE OFF

-- Step 1: De-duplicate existing rows.
-- For every cr_number with more than one non-deleted row, keep only the
-- one with the highest task_list_id (most recently created/updated —
-- IDENTITY columns are monotonically increasing) and soft-delete the rest.
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM (
    SELECT cr_number FROM crms_task_list
    WHERE is_deleted = 0 AND cr_number IS NOT NULL
    GROUP BY cr_number HAVING COUNT(*) > 1
  );

  IF v_count > 0 THEN
    UPDATE crms_task_list t
    SET is_deleted = 1
    WHERE is_deleted = 0
      AND cr_number IS NOT NULL
      AND task_list_id NOT IN (
        SELECT MAX(task_list_id) FROM crms_task_list
        WHERE is_deleted = 0 AND cr_number IS NOT NULL
        GROUP BY cr_number
      );
    DBMS_OUTPUT.PUT_LINE('De-duplicated ' || v_count || ' cr_number group(s) — kept most recent row, soft-deleted the rest.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('No duplicate cr_number rows found — nothing to de-duplicate.');
  END IF;
END;
/

-- Step 2: Unique index — enforces at most one non-deleted row per
-- cr_number going forward. Oracle excludes NULL index-key values from
-- uniqueness checks, so soft-deleted rows (which evaluate to NULL here)
-- and rows with a NULL cr_number are unaffected.
DECLARE
  v NUMBER;
BEGIN
  SELECT COUNT(*) INTO v FROM user_indexes WHERE index_name = 'UQ_TL_CR_NUMBER_ACTIVE';
  IF v = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE UNIQUE INDEX uq_tl_cr_number_active
      ON crms_task_list (CASE WHEN is_deleted = 0 THEN cr_number END)';
    DBMS_OUTPUT.PUT_LINE('CREATED: uq_tl_cr_number_active');
  ELSE
    DBMS_OUTPUT.PUT_LINE('EXISTS:  uq_tl_cr_number_active');
  END IF;
END;
/

COMMIT;
DBMS_OUTPUT.PUT_LINE('Task List de-dupe + uniqueness guard complete.');
