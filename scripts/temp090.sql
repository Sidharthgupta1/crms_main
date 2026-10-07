CREATE OR REPLACE PACKAGE xxcrms_email_pkg AS
  PROCEDURE send_mail (
    p_to         IN  VARCHAR2,                 -- ';'-separated recipient list
    p_cc         IN  VARCHAR2 DEFAULT NULL,     -- ';'-separated CC list (from crms_users.cc_email_address)
    p_subject    IN  VARCHAR2,
    p_body_html  IN  VARCHAR2,                  -- HTML body
    x_errbuf     OUT VARCHAR2                   -- NULL on success, error text on failure
  );
END xxcrms_email_pkg;
/
SHOW ERRORS

CREATE OR REPLACE PACKAGE BODY xxcrms_email_pkg AS

  g_from       CONSTANT VARCHAR2(240) := APPS.fnd_profile.VALUE ('XXMSSL FROM MAIL OCS');
  g_mail_host  CONSTANT VARCHAR2(240) := APPS.fnd_profile.VALUE ('XXMSSL_MAIL_HOST');
  g_mail_port  CONSTANT PLS_INTEGER   := 25;
  g_helo_name  CONSTANT VARCHAR2(60)  := 'crms-app';
  g_chunk_len  CONSTANT PLS_INTEGER   := 1000;  -- conservative per-call size for WRITE_DATA

  TYPE t_addr_list IS TABLE OF VARCHAR2(320);

  -- Splits a ';'-separated address string into a list, trimming blanks.
  FUNCTION split_addrs(p_list VARCHAR2) RETURN t_addr_list IS
    l_result t_addr_list := t_addr_list();
    l_rest   VARCHAR2(4000) := p_list;
    l_pos    PLS_INTEGER;
    l_addr   VARCHAR2(320);
  BEGIN
    IF p_list IS NULL THEN RETURN l_result; END IF;
    LOOP
      l_pos := INSTR(l_rest, ';');
      IF l_pos = 0 THEN
        l_addr := TRIM(l_rest);
        IF l_addr IS NOT NULL THEN
          l_result.EXTEND;
          l_result(l_result.COUNT) := l_addr;
        END IF;
        EXIT;
      ELSE
        l_addr := TRIM(SUBSTR(l_rest, 1, l_pos - 1));
        IF l_addr IS NOT NULL THEN
          l_result.EXTEND;
          l_result(l_result.COUNT) := l_addr;
        END IF;
        l_rest := SUBSTR(l_rest, l_pos + 1);
      END IF;
    END LOOP;
    RETURN l_result;
  END split_addrs;

  -- Writes a long string to the SMTP DATA stream in safe fixed-size chunks.
  PROCEDURE write_chunked(p_conn IN OUT NOCOPY utl_smtp.connection, p_text VARCHAR2) IS
    l_len PLS_INTEGER := NVL(LENGTH(p_text), 0);
    l_pos PLS_INTEGER := 1;
  BEGIN
    WHILE l_pos <= l_len LOOP
      utl_smtp.write_data(p_conn, SUBSTR(p_text, l_pos, g_chunk_len));
      l_pos := l_pos + g_chunk_len;
    END LOOP;
  END write_chunked;

  PROCEDURE send_mail (
    p_to         IN  VARCHAR2,
    p_cc         IN  VARCHAR2 DEFAULT NULL,
    p_subject    IN  VARCHAR2,
    p_body_html  IN  VARCHAR2,
    x_errbuf     OUT VARCHAR2
  ) IS
    l_conn   utl_smtp.connection;
    l_to     t_addr_list;
    l_cc     t_addr_list;
    l_to_hdr VARCHAR2(4000) := '';
    l_cc_hdr VARCHAR2(4000) := '';
  BEGIN
    x_errbuf := NULL;

    IF p_to IS NULL THEN
      x_errbuf := 'No recipient (p_to) supplied';
      RETURN;
    END IF;

    l_to := split_addrs(p_to);
    l_cc := split_addrs(p_cc);

    IF l_to.COUNT = 0 THEN
      x_errbuf := 'No valid recipient after parsing p_to';
      RETURN;
    END IF;

    FOR i IN 1 .. l_to.COUNT LOOP
      l_to_hdr := l_to_hdr || CASE WHEN i > 1 THEN ', ' END || l_to(i);
    END LOOP;
    FOR i IN 1 .. l_cc.COUNT LOOP
      l_cc_hdr := l_cc_hdr || CASE WHEN i > 1 THEN ', ' END || l_cc(i);
    END LOOP;

    l_conn := utl_smtp.open_connection(g_mail_host, g_mail_port);
    utl_smtp.helo(l_conn, g_helo_name);
    utl_smtp.mail(l_conn, g_from);

    FOR i IN 1 .. l_to.COUNT LOOP
      utl_smtp.rcpt(l_conn, l_to(i));
    END LOOP;
    FOR i IN 1 .. l_cc.COUNT LOOP
      utl_smtp.rcpt(l_conn, l_cc(i));
    END LOOP;

    utl_smtp.open_data(l_conn);
    utl_smtp.write_data(l_conn, 'Date: ' || TO_CHAR(SYSTIMESTAMP, 'DY, DD Mon YYYY HH24:MI:SS') || ' +0530' || UTL_TCP.CRLF);
    utl_smtp.write_data(l_conn, 'From: ' || g_from || UTL_TCP.CRLF);
    utl_smtp.write_data(l_conn, 'To: ' || l_to_hdr || UTL_TCP.CRLF);
    IF l_cc_hdr IS NOT NULL THEN
      utl_smtp.write_data(l_conn, 'Cc: ' || l_cc_hdr || UTL_TCP.CRLF);
    END IF;
    utl_smtp.write_data(l_conn, 'Subject: ' || p_subject || UTL_TCP.CRLF);
    utl_smtp.write_data(l_conn, 'MIME-Version: 1.0' || UTL_TCP.CRLF);
    utl_smtp.write_data(l_conn, 'Content-Type: text/html; charset=UTF-8' || UTL_TCP.CRLF);
    utl_smtp.write_data(l_conn, UTL_TCP.CRLF);
    write_chunked(l_conn, p_body_html);
    utl_smtp.close_data(l_conn);
    utl_smtp.quit(l_conn);
  EXCEPTION
    WHEN OTHERS THEN
      x_errbuf := SQLERRM;
      DBMS_OUTPUT.PUT_LINE('XXCRMS_EMAIL_PKG.send_mail exception: ' || SQLERRM);
      BEGIN utl_smtp.quit(l_conn); EXCEPTION WHEN OTHERS THEN NULL; END;
  END send_mail;

END xxcrms_email_pkg;
/
SHOW ERRORS


============================

declare
v_errorbuf VARCHAR2(4000);
begin
  crms_user.xxcrms_email_pkg.send_mail (
    p_to       =>  'Harsh.Raj@motherson.com',
    p_cc       =>  'Sidharth.Gupta@motherson.com', --VARCHAR2 DEFAULT NULL,
    p_subject  =>   'Hi',
    p_body_html =>  NULL,
  x_errbuf    => v_errorbuf
  );
end;
/

=============================================================

SELECT table_name, column_name FROM user_tab_columns
WHERE column_name IN ('RELEASE_ID','CR_NUMBER','RELEASE_NUMBER')
ORDER BY table_name;


222

select * from CRMS_RELEASES where release_number = 'RLSE0000103'