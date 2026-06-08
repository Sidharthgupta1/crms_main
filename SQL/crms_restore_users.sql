-- ============================================================
-- CRMS — Restore Users After Truncate
-- Run as: APPS user in SQL Developer
-- ============================================================
SET SERVEROUTPUT ON
SET DEFINE OFF

BEGIN

  -- ── Insert Users ─────────────────────────────────────────
  -- Sandeep Gupta (Admin)  password: admin123
  INSERT INTO crms_users (initials, full_name, role, password_hash, is_active)
  VALUES ('SG', 'Sidharth Gupta', 'admin', '$2a$12$fmMSiVG5w6PcuZDbCqqA2.zkZb7zPqB9GdZ4rnZPPvVsgGktfBn6i', 1);

  -- Rohit Kumar (User)  password: pass123
  INSERT INTO crms_users (initials, full_name, role, password_hash, is_active)
  VALUES ('BN', 'Bhupesh Nischal', 'user', '$2a$12$lN1qdsKPdA0rn4.1Ov2On.eUaIZfQTz31ktGrJ.doAu3VyTK/3unu', 1);

  -- Priya Mehta (User)  password: pass123
  INSERT INTO crms_users (initials, full_name, role, password_hash, is_active)
  VALUES ('AC', 'Ankur Chaudhary', 'user', '$2a$12$lN1qdsKPdA0rn4.1Ov2On.eUaIZfQTz31ktGrJ.doAu3VyTK/3unu', 1);

  -- Amit Verma (User)  password: pass123
  INSERT INTO crms_users (initials, full_name, role, password_hash, is_active)
  VALUES ('AG', 'Amit Garg', 'user', '$2a$12$lN1qdsKPdA0rn4.1Ov2On.eUaIZfQTz31ktGrJ.doAu3VyTK/3unu', 1);

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('4 users inserted successfully.');
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('Login credentials:');
  DBMS_OUTPUT.PUT_LINE('  SG / admin123  (Admin)');
  DBMS_OUTPUT.PUT_LINE('  BN / pass123   (User)');
  DBMS_OUTPUT.PUT_LINE('  AC / pass123   (User)');
  DBMS_OUTPUT.PUT_LINE('  AG / pass123   (User)');

EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
END;
/

-- Verify
SELECT user_id, initials, full_name, role,
       SUBSTR(password_hash,1,10) AS hash_prefix,
       is_active
FROM   crms_users
ORDER  BY initials;
