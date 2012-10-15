----------------------------------------------------------------------------------------------------
insert into system.br(id, technical_type_code, feedback) 
values('action_others_must_be_marked_as_done', 'sql', 
'There are other actions that must be completed before to proceed with this action');

insert into system.br_definition(br_id, active_from, active_until, body) 
values('action_others_must_be_marked_as_done', now(), 'infinity', 
'select is_done as vl
from application.application_action a 
  inner join application.application_action_type a_t on a.type_code = a_t.code
where next_status_type_code is null and a.status_id in (select status_id 
  from application.application_action where id = #{id})
order by 1
limit 1');

insert into system.br_validation(br_id, severity_code, target_code, order_of_execution, target_action_type_code) 
select 'action_others_must_be_marked_as_done', 'critical', 'application-action', 1, code
from application.application_action_type  
where next_status_type_code is not null;
----------------------------------------------------------------------------------------------------

update system.br set display_name = id where display_name !=id;

