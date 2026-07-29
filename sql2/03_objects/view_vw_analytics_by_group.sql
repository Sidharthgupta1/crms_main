-- VW_ANALYTICS_BY_GROUP
CREATE OR REPLACE FORCE NONEDITIONABLE VIEW "VW_ANALYTICS_BY_GROUP" ("GROUP_ID", "GROUP_NAME", "TOTAL_RELEASES", "OPEN_RELEASES", "CLOSED_RELEASES", "CANCELLED_RELEASES", "CRITICAL_OPEN") AS 
  SELECT
            ag.group_id,
            ag.group_name,
            COUNT(r.release_id)                                           AS total_releases,
            COUNT(CASE WHEN r.state NOT IN ('Closed','Cancelled') THEN 1 END) AS open_releases,
            COUNT(CASE WHEN r.state = 'Closed'    THEN 1 END)            AS closed_releases,
            COUNT(CASE WHEN r.state = 'Cancelled' THEN 1 END)            AS cancelled_releases,
            COUNT(CASE WHEN r.priority = '1' AND r.state NOT IN ('Closed','Cancelled') THEN 1 END) AS critical_open
          FROM crms_assignment_groups ag
          LEFT JOIN crms_releases r
            ON r.assignment_group_id = ag.group_id AND r.is_deleted = 0
          GROUP BY ag.group_id, ag.group_name;
