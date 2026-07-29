# CRMS database replication package

Generated from localhost:1521/FREEPDB1 on 2026-07-29T06:08:07.889Z.

Run `00_run_all.sql` in SQL*Plus, SQLcl, or Oracle SQL Developer while connected to the target schema.
The package creates the CRMS tables in foreign-key dependency order, loads the configuration data that is independent of users, and then creates supporting objects.

`CRMS_USERS` is deliberately created without rows so the target environment can add its own users.
`USER_SESSIONS` is also structure-only: it contains refresh-token/session state and must not be copied between environments.

Rows from tables that depend on `CRMS_USERS` are not loaded, because copying them without their referenced users would violate foreign keys and produce a broken database. Their table structures are fully included. After users are added in the target environment, create new releases, approvals, tasks, memberships, and other operational records there.
