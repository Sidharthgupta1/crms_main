ALTER TABLE crms_users ADD cc_email_address VARCHAR2(500)

select * from crms_users

update crms_users set email_address = 'Ankur.Dawra@motherson.com'
where full_name = 'Ankur Dawra'

update crms_users set CC_email_address = 'Sidharth.Gupta@motherson.com'
where full_name = 'Bhupesh Nischal'

commit

select * from all_objects where object_name = 'xxmssl_email_pkg'

GRANT EXECUTE ON crms_user.xxcrms_email_pkg TO crms_user;

GRANT EXECUTE ON apps.xxcrms_email_pkg TO crms_user;


select apps.FND_PROFILE.VALUE ('XXMSSL_MAIL_HOST') from dual;

select * from APPLSYS.fnd_profile_options_tl


from_name:- ASCP01@mssl.motherson.com 

host:- 