-- VW_COMPANY_GROUP_PHASE
CREATE OR REPLACE FORCE NONEDITIONABLE VIEW "VW_COMPANY_GROUP_PHASE" ("PHASE_MAP_ID", "COMPANY_ID", "COMPANY_NAME", "SERVICE_ID", "SERVICE_NAME", "GROUP_ID", "GROUP_NAME", "PHASE_CODE") AS 
  SELECT
  m.phase_map_id,
  m.company_id,
  c.company_name,
  m.service_id,
  s.service_name,
  m.group_id,
  g.group_name,
  m.phase_code
FROM crms_company_group_phase_map m
JOIN crms_companies         c ON c.company_id  = m.company_id
JOIN crms_services          s ON s.service_id  = m.service_id
JOIN crms_assignment_groups g ON g.group_id    = m.group_id;
