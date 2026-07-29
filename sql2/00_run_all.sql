WHENEVER SQLERROR EXIT SQL.SQLCODE
SET DEFINE OFF
SET SQLBLANKLINES ON

PROMPT Creating CRMS tables...
@@01_sequences.sql
@@01_schema/001_crms_assignment_groups.sql
@@01_schema/002_crms_companies.sql
@@01_schema/003_crms_modules.sql
@@01_schema/004_crms_approval_groups.sql
@@01_schema/005_crms_module_groups.sql
@@01_schema/006_crms_phase_groups.sql
@@01_schema/007_crms_services.sql
@@01_schema/008_crms_company_group_phase_map.sql
@@01_schema/009_crms_company_service_map.sql
@@01_schema/010_crms_users.sql
@@01_schema/011_crms_approval_flows.sql
@@01_schema/012_crms_approval_flow_approvers.sql
@@01_schema/013_crms_audit.sql
@@01_schema/014_crms_group_members.sql
@@01_schema/015_crms_module_users.sql
@@01_schema/016_crms_phase_process_owners.sql
@@01_schema/017_crms_phase_reviewers.sql
@@01_schema/018_crms_phase_templates.sql
@@01_schema/019_crms_releases.sql
@@01_schema/020_crms_attachments.sql
@@01_schema/021_crms_comments.sql
@@01_schema/022_crms_notifications.sql
@@01_schema/023_crms_release_approvals.sql
@@01_schema/024_crms_release_history.sql
@@01_schema/025_crms_release_phase_groups.sql
@@01_schema/026_crms_release_tasks.sql
@@01_schema/027_crms_review_requests.sql
@@01_schema/028_crms_tasks.sql
@@01_schema/029_crms_task_list.sql
@@01_schema/030_crms_task_list_editors.sql
@@01_schema/031_user_sessions.sql

PROMPT Loading CRMS data...
@@02_data/001_crms_assignment_groups.sql
@@02_data/002_crms_companies.sql
@@02_data/003_crms_modules.sql
@@02_data/004_crms_approval_groups.sql
@@02_data/005_crms_module_groups.sql
@@02_data/006_crms_phase_groups.sql
@@02_data/007_crms_services.sql
@@02_data/008_crms_company_group_phase_map.sql
@@02_data/009_crms_company_service_map.sql

PROMPT Creating views, triggers, procedures, and jobs...
@@03_objects/view_vw_analytics_by_group.sql
@@03_objects/view_vw_company_group_phase.sql
@@03_objects/view_vw_releases_summary.sql
@@03_objects/trigger_trg_releases_updated_at.sql
@@03_objects/trigger_trg_tasks_updated_at.sql
@@03_objects/trigger_trg_task_list_updated_at.sql
@@03_objects/procedure_crms_session_cleanup_proc.sql

PROMPT CRMS replication package completed.
EXIT SUCCESS
