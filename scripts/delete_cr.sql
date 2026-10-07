SET SERVEROUTPUT ON
SET DEFINE OFF

DECLARE
  v_release_id crms_releases.release_id%TYPE := 222;  -- ◄◄◄ EDIT THIS
BEGIN
  FOR r IN (
    SELECT release_number, title, state, requested_by
    FROM crms_releases WHERE release_id = v_release_id
  ) LOOP
    DBMS_OUTPUT.PUT_LINE('About to delete: ' || r.release_number || ' — "' || r.title || '" (state: ' || r.state || ')');
  END LOOP;

  FOR r IN (
    SELECT 'crms_release_tasks'        AS tbl, COUNT(*) AS cnt FROM crms_release_tasks        WHERE release_id = v_release_id UNION ALL
    SELECT 'crms_release_approvals',            COUNT(*)       FROM crms_release_approvals    WHERE release_id = v_release_id UNION ALL
    SELECT 'crms_release_history',              COUNT(*)       FROM crms_release_history      WHERE release_id = v_release_id UNION ALL
    SELECT 'crms_release_phase_groups',         COUNT(*)       FROM crms_release_phase_groups WHERE release_id = v_release_id UNION ALL
    SELECT 'crms_review_requests',              COUNT(*)       FROM crms_review_requests      WHERE release_id = v_release_id UNION ALL
    SELECT 'crms_attachments',                  COUNT(*)       FROM crms_attachments          WHERE release_id = v_release_id UNION ALL
    SELECT 'crms_comments',                     COUNT(*)       FROM crms_comments             WHERE release_id = v_release_id UNION ALL
    SELECT 'crms_notifications',                COUNT(*)       FROM crms_notifications        WHERE release_id = v_release_id UNION ALL
    SELECT 'crms_tasks (legacy)',               COUNT(*)       FROM crms_tasks                WHERE release_id = v_release_id
  ) LOOP
    DBMS_OUTPUT.PUT_LINE('  ' || RPAD(r.tbl, 28) || ' : ' || r.cnt || ' row(s)');
  END LOOP;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('No release found with release_id = ' || v_release_id || ' — check the ID before continuing.');
END;
/


=================================

DECLARE
  v_release_id crms_releases.release_id%TYPE := 222;  -- ◄◄◄ EDIT THIS (same as Step 1)
  v_release_no crms_releases.release_number%TYPE;
  v_count      NUMBER;
BEGIN
  SELECT release_number INTO v_release_no FROM crms_releases WHERE release_id = v_release_id;

  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE('CRMS — Deleting release ' || v_release_no || ' (release_id=' || v_release_id || ')');
  DBMS_OUTPUT.PUT_LINE('==============================================');

  -- Break the attachments <-> sub-tasks circular reference first
  -- (crms_release_tasks.upload_attachment_id points at crms_attachments)
  UPDATE crms_release_tasks SET upload_attachment_id = NULL WHERE release_id = v_release_id;

  DELETE FROM crms_attachments WHERE release_id = v_release_id;
  v_count := SQL%ROWCOUNT; DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_attachments');

  DELETE FROM crms_release_tasks WHERE release_id = v_release_id;
  v_count := SQL%ROWCOUNT; DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_release_tasks');

  DELETE FROM crms_release_approvals WHERE release_id = v_release_id;
  v_count := SQL%ROWCOUNT; DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_release_approvals');

  DELETE FROM crms_review_requests WHERE release_id = v_release_id;
  v_count := SQL%ROWCOUNT; DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_review_requests');

  DELETE FROM crms_release_phase_groups WHERE release_id = v_release_id;
  v_count := SQL%ROWCOUNT; DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_release_phase_groups');

  DELETE FROM crms_comments WHERE release_id = v_release_id;
  v_count := SQL%ROWCOUNT; DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_comments');

  DELETE FROM crms_notifications WHERE release_id = v_release_id;
  v_count := SQL%ROWCOUNT; DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_notifications');

  DELETE FROM crms_release_history WHERE release_id = v_release_id;
  v_count := SQL%ROWCOUNT; DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_release_history');

  -- Legacy task system (separate from crms_release_tasks)
  DELETE FROM crms_tasks WHERE release_id = v_release_id;
  v_count := SQL%ROWCOUNT; DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_tasks (legacy)');

  -- Task List is keyed by release_number text, not release_id
  DELETE FROM crms_task_list WHERE cr_number = v_release_no;
  v_count := SQL%ROWCOUNT; DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_task_list');

  -- Optional — audit log is kept by default (matches your existing
  -- test_cr_delete.sql convention). Uncomment to also purge it:
  -- DELETE FROM crms_audit WHERE cr_number = v_release_no;

  -- Parent row, last
  DELETE FROM crms_releases WHERE release_id = v_release_id;
  v_count := SQL%ROWCOUNT; DBMS_OUTPUT.PUT_LINE('Deleted ' || v_count || ' rows from crms_releases');

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE('Done. Release ' || v_release_no || ' and all related data deleted.');
  DBMS_OUTPUT.PUT_LINE('==============================================');
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('No release found with release_id = ' || v_release_id || ' — nothing deleted.');
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE('All changes rolled back — nothing was deleted.');
END;
/