select * from dba_objects where object_name like '%CRMS%';


SELECT * FROM CRMS_users;

create index idx_crm_users_is_active on CRMS_users (is_active)

commit;

select * from CRMS_RELEASE_APPROVALS;

select * from CRMS_NOTIFICATIONS;

SELECT * FROM CRMS_RELEASES;

SELECT * FROM CRMS_RELEASE_HISTORY;