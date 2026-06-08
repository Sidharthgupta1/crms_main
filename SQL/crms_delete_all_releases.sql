-- ============================================================
-- CRMS — Delete ALL Releases & Related Data
-- Run as: APPS user in SQL Developer
-- WARNING: This permanently deletes ALL CR data.
--          Keeps: Users, Groups, Companies, Services, Modules,
--                 Approval flows, Phase group mappings, Audit log
-- ============================================================

SET SERVEROUTPUT ON
SET DEFINE OFF

DECLARE
  v_count NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE('CRMS — Deleting all release data');
  DBMS_OUTPUT.PUT_LINE('Time: ' || TO_CHAR(SYSDATE,'DD-MON-YYYY HH24:MI:SS'));
  DBMS_OUTPUT.PUT_LINE('==============================================');

  -- ── Step 1: Child tables of crms_releases (delete first) ──────────

  DELETE FROM crms_release_approvals;
  v_count := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_release_approvals');

  DELETE FROM crms_release_history;
  v_count := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_release_history');

  DELETE FROM crms_release_phase_groups;
  v_count := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_release_phase_groups');

  DELETE FROM crms_attachments;
  v_count := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_attachments');

  DELETE FROM crms_comments;
  v_count := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_comments');

  DELETE FROM crms_notifications;
  v_count := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_notifications');

  -- ── Step 2: Sub-tasks (crms_release_tasks) ────────────────────────

  DELETE FROM crms_release_tasks;
  v_count := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_release_tasks');

  -- Legacy tasks table (if exists)
  BEGIN
    EXECUTE IMMEDIATE 'DELETE FROM crms_tasks';
    DBMS_OUTPUT.PUT_LINE('Deleted from crms_tasks (legacy)');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- ── Step 3: Parent table — crms_releases ──────────────────────────

  DELETE FROM crms_releases;
  v_count := SQL%ROWCOUNT;
  DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_releases');

  -- ── Step 4: Reset sequences so numbering starts fresh ─────────────

  -- Reset release sequence back to start
  -- (Oracle doesn't support ALTER SEQUENCE RESTART directly before 18c,
  --  so we drop and recreate)
  BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE crms_release_seq';
    EXECUTE IMMEDIATE '
      CREATE SEQUENCE crms_release_seq
        START WITH  1
        INCREMENT BY 1
        NOCACHE
        NOCYCLE';
    DBMS_OUTPUT.PUT_LINE('Reset crms_release_seq → starts at RLSE0000001');
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('WARN: Could not reset crms_release_seq — ' || SQLERRM);
  END;

  BEGIN
    EXECUTE IMMEDIATE 'DROP SEQUENCE crms_rtask_seq';
    EXECUTE IMMEDIATE '
      CREATE SEQUENCE crms_rtask_seq
        START WITH  1
        INCREMENT BY 1
        NOCACHE
        NOCYCLE';
    DBMS_OUTPUT.PUT_LINE('Reset crms_rtask_seq  → starts at RTSK0000001');
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('WARN: Could not reset crms_rtask_seq — ' || SQLERRM);
  END;

  -- ── Step 5: Optionally clear audit log (comment out to keep) ───────
  -- DELETE FROM crms_audit;
  -- DBMS_OUTPUT.PUT_LINE('Cleared crms_audit log');

  COMMIT;

  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE('Done. All releases deleted. Sequences reset.');
  DBMS_OUTPUT.PUT_LINE('Users, Groups, Modules, Approval flows kept.');
  DBMS_OUTPUT.PUT_LINE('==============================================');

EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
  DBMS_OUTPUT.PUT_LINE('All changes rolled back.');
END;
/

-- ── Verify counts after deletion ──────────────────────────────────────
SELECT 'crms_releases'          AS tbl, COUNT(*) AS remaining FROM crms_releases         UNION ALL
SELECT 'crms_release_history',           COUNT(*) FROM crms_release_history               UNION ALL
SELECT 'crms_release_tasks',             COUNT(*) FROM crms_release_tasks                 UNION ALL
SELECT 'crms_release_approvals',         COUNT(*) FROM crms_release_approvals             UNION ALL
SELECT 'crms_release_phase_groups',      COUNT(*) FROM crms_release_phase_groups          UNION ALL
SELECT 'crms_attachments',               COUNT(*) FROM crms_attachments                   UNION ALL
SELECT 'crms_comments',                  COUNT(*) FROM crms_comments                      UNION ALL
SELECT 'crms_notifications',             COUNT(*) FROM crms_notifications                 UNION ALL
SELECT '─── KEPT ─────────────',         0        FROM dual                               UNION ALL
SELECT 'crms_users',                     COUNT(*) FROM crms_users                         UNION ALL
SELECT 'crms_assignment_groups',         COUNT(*) FROM crms_assignment_groups             UNION ALL
SELECT 'crms_modules',                   COUNT(*) FROM crms_modules                       UNION ALL
SELECT 'crms_phase_groups',              COUNT(*) FROM crms_phase_groups                  UNION ALL
SELECT 'crms_approval_flows',            COUNT(*) FROM crms_approval_flows
ORDER BY 1;
