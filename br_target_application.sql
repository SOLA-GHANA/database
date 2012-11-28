
----------------------------------------------------------------------------------------------------
insert into system.br(id, technical_type_code, feedback) 
values('application-br7-check-sources-have-documents', 'sql', 
'Some of the documents for this application do not have an attached scanned image' );

insert into system.br_definition(br_id, active_from, active_until, body) 
values('application-br7-check-sources-have-documents', now(), 'infinity', 
'select ext_archive_id is not null as vl
from source.source 
where id in (select source_id 
    from application.application_uses_source
    where application_id= #{id})');

insert into system.br_validation(br_id, severity_code, target_operation_code, target_code, order_of_execution) 
values('application-br7-check-sources-have-documents', 'warning', 'validate', 'application', 2);

----------------------------------------------------------------------------------------------------
insert into system.br(id, technical_type_code, feedback) 
values('application-br1-check-required-sources-are-present', 'sql', 
'All documents required for the services are present.' );

insert into system.br_definition(br_id, active_from, active_until, body) 
values('application-br1-check-required-sources-are-present', now(), 'infinity', 
'select count(*) =0  as vl
from application.request_type_requires_source_type r_s 
where request_type_code in (
  select request_type_code 
  from application.application where id=#{id})
and not exists (
  select s.type_code
  from application.application_uses_source a_s inner join source.source s on a_s.source_id= s.id
  where a_s.application_id= #{id} and s.type_code = r_s.source_type_code
)');

insert into system.br_validation(br_id, severity_code, target_operation_code, target_code, order_of_execution) 
values('application-br1-check-required-sources-are-present', 'critical', 'validate', 'application', 3);

----------------------------------------------------------------------------------------------------
insert into system.br(id, technical_type_code, feedback) 
values('application-br4-check-sources-date-not-in-the-future', 'sql', 
'No documents have submission dates for the future.' );

insert into system.br_definition(br_id, active_from, active_until, body) 
values('application-br4-check-sources-date-not-in-the-future', now(), 'infinity', 
'select s.submission < now() as vl
from application.application_uses_source a_s inner join source.source s on a_s.source_id= s.id
where a_s.application_id = #{id}
order by 1
limit 1
');

insert into system.br_validation(br_id, severity_code, target_operation_code, target_code, order_of_execution) 
values('application-br4-check-sources-date-not-in-the-future', 'warning', 'validate', 'application', 6);
----------------------------------------------------------------------------------------------------
insert into system.br(id, technical_type_code, feedback) 
values('application-fee-paid', 'sql', 
'The fee application must be fully paid.' );

insert into system.br_definition(br_id, active_from, active_until, body) 
values('application-fee-paid', now(), 'infinity', 
'select (total_amount_paid = total_fee and total_fee>0) as vl
from application.application
where id = #{id}');

insert into system.br_validation(br_id, severity_code, target_operation_code, target_code, order_of_execution) 
values('application-fee-paid', 'critical', 'validate', 'application', 5);
----------------------------------------------------------------------------------------------------

insert into system.br(id, technical_type_code, feedback) 
values('application-regional-no-surveyor-present', 'sql', 
'The application must have a licenced surveyor.' );

insert into system.br_definition(br_id, active_from, active_until, body) 
values('application-regional-no-surveyor-present', now(), 'infinity', 
'select count(*)>0 as vl
from application.application_party
where application_id = #{id} and role_code = ''certifiedSurveyor''
');

insert into system.br_validation(br_id, severity_code, target_operation_code, target_code, target_request_type_code, order_of_execution) 
values('application-regional-no-surveyor-present', 'critical', 'validate', 'application', 'smd-regnr', 7);
----------------------------------------------------------------------------------------------------
insert into system.br(id, technical_type_code, feedback) 
values('application-regional-no-client-present', 'sql', 
'The application must have a client.' );

insert into system.br_definition(br_id, active_from, active_until, body) 
values('application-regional-no-client-present', now(), 'infinity', 
'select count(*)>0 as vl
from application.application_party
where application_id = #{id} and role_code = ''client''
');

insert into system.br_validation(br_id, severity_code, target_operation_code, target_code, target_request_type_code, order_of_execution) 
values('application-regional-no-client-present', 'critical', 'validate', 'application', 'smd-regnr', 7);
----------------------------------------------------------------------------------------------------
insert into system.br(id, technical_type_code, feedback) 
values('application-party-present', 'sql', 
'The application must have at least a party present.' );

insert into system.br_definition(br_id, active_from, active_until, body) 
values('application-party-present', now(), 'infinity', 
'select count(*)>0 as vl
from application.application_party
where application_id = #{id}');

insert into system.br_validation(br_id, severity_code, target_operation_code, target_code, target_request_type_code, order_of_execution) 
values('application-party-present', 'critical', 'validate', 'application', 'smd-plancertification', 7);

insert into system.br_validation(br_id, severity_code, target_operation_code, target_code, target_request_type_code, order_of_execution) 
values('application-party-present', 'critical', 'validate', 'application', 'cadastreChange', 7);

insert into system.br_validation(br_id, severity_code, target_operation_code, target_code, target_request_type_code, order_of_execution) 
values('application-party-present', 'critical', 'validate', 'application', 'redefineCadastre', 7);
----------------------------------------------------------------------------------------------------

insert into system.br(id, technical_type_code, feedback) 
values('application-plan-approval-multiple-requests', 'sql', 
'There should not be ongoing or fullfilled requests for the same spatial unit.' );

insert into system.br_definition(br_id, active_from, active_until, body) 
values('application-plan-approval-multiple-requests', now(), 'infinity', 
'select count(*)=0 as vl
from application.plan_certification_request others
  inner join application.plan_certification_request target on others.spatial_unit_id= target.spatial_unit_id 
where target.application_id = #{id}
  and others.application_id != #{id}');

insert into system.br_validation(br_id, severity_code, target_operation_code, target_code, target_request_type_code, order_of_execution) 
values('application-plan-approval-multiple-requests', 'warning', 'validate', 'application', 'smd-plancertification', 7);
----------------------------------------------------------------------------------------------------

insert into system.br(id, technical_type_code, feedback) 
values('application-change-only-by-assigned-user', 'sql', 
'Only the assinged user is allowed to change the application.' );

insert into system.br_definition(br_id, active_from, active_until, body) 
values('application-change-only-by-assigned-user', now(), 'infinity', 
'select assignee_id = (select id from system.appuser where username = #{current_user}) as vl
from application.application
where id = #{id}');

insert into system.br_validation(br_id, severity_code, target_operation_code, target_code, order_of_execution) 
values('application-change-only-by-assigned-user', 'critical', 'change', 'application', 7);
----------------------------------------------------------------------------------------------------

update system.br set display_name = id where display_name !=id;

