-- VW_RELEASES_SUMMARY
CREATE OR REPLACE FORCE NONEDITIONABLE VIEW "VW_RELEASES_SUMMARY" ("RELEASE_ID", "RELEASE_NUMBER", "STATE", "PRIORITY", "PRIORITY_LABEL", "TITLE", "COMPANY", "SERVICE", "PLANNED_START_DATE", "TARGET_END_DATE", "SLA_AGE_DAYS", "REQUESTED_BY", "ASSIGNED_TO", "ASSIGNMENT_GROUP", "CREATED_AT", "UPDATED_AT", "TASK_COUNT", "OPEN_TASK_COUNT", "COMMENT_COUNT") AS 
  SELECT
            r.release_id,
            r.release_number,
            r.state,
            r.priority,
            CASE r.priority
              WHEN '1' THEN '1 – Critical' WHEN '2' THEN '2 – High'
              WHEN '3' THEN '3 – Moderate' WHEN '4' THEN '4 – Low'
              ELSE r.priority
            END AS priority_label,
            r.title,
            r.company,
            r.service,
            r.planned_start_date,
            r.target_end_date,
            TRUNC(SYSDATE - r.planned_start_date)          AS sla_age_days,
            u_req.full_name                                 AS requested_by,
            u_ass.full_name                                 AS assigned_to,
            ag.group_name                                   AS assignment_group,
            r.created_at,
            r.updated_at,
            (SELECT COUNT(*) FROM crms_tasks t WHERE t.release_id = r.release_id)       AS task_count,
            (SELECT COUNT(*) FROM crms_tasks t WHERE t.release_id = r.release_id
               AND t.state = 'Open')                                                     AS open_task_count,
            (SELECT COUNT(*) FROM crms_comments c WHERE c.release_id = r.release_id)    AS comment_count
          FROM  crms_releases r
          JOIN  crms_users u_req ON u_req.user_id = r.requested_by
          LEFT  JOIN crms_users u_ass ON u_ass.user_id = r.assigned_to_user_id
          LEFT  JOIN crms_assignment_groups ag ON ag.group_id = r.assignment_group_id
          WHERE r.is_deleted = 0;
