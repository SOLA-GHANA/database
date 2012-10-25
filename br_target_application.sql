
----------------------------------------------------------------------------------------------------
insert into system.br(id, technical_type_code, feedback) 
values('application-br7-check-sources-have-documents', 'sql', 
'Some of the documents for this application do not have an attached scanned image::::Alcuni dei documenti per questa pratica non hanno una immagine scannerizzata allegata' );

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
'All documents required for the services are present.::::Sono presenti tutti i documenti richiesti per il servizio' );

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
'No documents have submission dates for the future.::::Nessun documento ha le date di inoltro per il futuro' );

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

update system.br set display_name = id where display_name !=id;

