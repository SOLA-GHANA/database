
-- Starting up the database script generation
ALTER DATABASE sola SET bytea_output TO 'escape';
    
--Create schema source--
DROP SCHEMA IF EXISTS source CASCADE;
        
CREATE SCHEMA source;

--Create schema party--
DROP SCHEMA IF EXISTS party CASCADE;
        
CREATE SCHEMA party;

--Create schema administrative--
DROP SCHEMA IF EXISTS administrative CASCADE;
        
CREATE SCHEMA administrative;

--Create schema cadastre--
DROP SCHEMA IF EXISTS cadastre CASCADE;
        
CREATE SCHEMA cadastre;

--Create schema application--
DROP SCHEMA IF EXISTS application CASCADE;
        
CREATE SCHEMA application;

--Create schema address--
DROP SCHEMA IF EXISTS address CASCADE;
        
CREATE SCHEMA address;

--Create schema system--
DROP SCHEMA IF EXISTS system CASCADE;
        
CREATE SCHEMA system;

--Create schema document--
DROP SCHEMA IF EXISTS document CASCADE;
        
CREATE SCHEMA document;

--Create schema transaction--
DROP SCHEMA IF EXISTS transaction CASCADE;
        
CREATE SCHEMA transaction;

--Adding handy common functions --

    --Adding trigger function to track changes--

--Adding trigger function to track changes--


--Adding functions --

-- Function public.f_for_trg_track_changes --
CREATE OR REPLACE FUNCTION public.f_for_trg_track_changes(

) RETURNS trigger 
AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF (NEW.rowversion != OLD.rowversion) THEN
            RAISE EXCEPTION 'row_has_different_change_time';
        END IF;
        IF (NEW.change_action != 'd') THEN
            NEW.change_action := 'u';
        END IF;
        IF OLD.rowversion > 200000000 THEN
            NEW.rowversion = 1;
        ELSE
            NEW.rowversion = OLD.rowversion + 1;
        END IF;
    ELSIF (TG_OP = 'INSERT') THEN
        NEW.change_action := 'i';
        NEW.rowversion = 1;
    END IF;
    NEW.change_time := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.f_for_trg_track_changes(

) IS 'This function is called from triggers in every table that has the columns to track changes. 
It also checks if the record has been already updated from another client application by checking the rowversion.';
    
-- Function public.f_for_trg_track_history --
CREATE OR REPLACE FUNCTION public.f_for_trg_track_history(

) RETURNS trigger 
AS $$
DECLARE
    table_name_main varchar;
    table_name_historic varchar;
    insert_col_part varchar;
    values_part varchar;
BEGIN
    table_name_main = TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME;
    table_name_historic = table_name_main || '_historic';
    insert_col_part = (select string_agg(column_name, ',') 
      from information_schema.columns  
      where table_schema= TG_TABLE_SCHEMA and table_name = TG_TABLE_NAME);
    values_part = '$1.' || replace(insert_col_part, ',' , ',$1.');

    IF (TG_OP = 'DELETE') THEN
        OLD.change_action := 'd';
    END IF;
    EXECUTE 'INSERT INTO ' || table_name_historic || '(' || insert_col_part || ') SELECT ' || values_part || ';' USING OLD;
    IF (TG_OP = 'DELETE') THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.f_for_trg_track_history(

) IS 'This function is called after a change is happening in a table to push the former values to the historic keeping table.';
    
-- Function public.fn_triggerall --
CREATE OR REPLACE FUNCTION public.fn_triggerall(
 doenable bool
) RETURNS integer 
AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN select * from information_schema.tables where table_type = 'BASE TABLE' and table_schema not in ('pg_catalog', 'information_schema')
  LOOP
    IF DoEnable THEN
      EXECUTE 'ALTER TABLE "'  || rec.table_schema || '"."' ||  rec.table_name || '" ENABLE TRIGGER ALL';
    ELSE
      EXECUTE 'ALTER TABLE "'  || rec.table_schema || '"."' ||  rec.table_name || '" DISABLE TRIGGER ALL';
    END IF; 
  END LOOP; 
  RETURN 1;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.fn_triggerall(
 doenable bool
) IS 'This function can be used to disable all triggers in the database.

<b>How to use </b>
to call to disable all triggers in all schemas in db
select fn_triggerall(false);

to call to enable all triggers in all schemas in db
select fn_triggerall(true);';
    
-- Function public.clean_db --
CREATE OR REPLACE FUNCTION public.clean_db(
 schema_name varchar
) RETURNS integer 
AS $$
DECLARE
  rec RECORD;

BEGIN
  FOR rec IN select * from information_schema.tables 
	where table_type = 'BASE TABLE' and table_schema = schema_name and table_name not in ('geometry_columns', 'spatial_ref_sys')
  LOOP
      EXECUTE 'DROP TABLE IF EXISTS "'  || rec.table_schema || '"."' ||  rec.table_name || '" CASCADE;';
  END LOOP;
  FOR rec IN select '"' || routine_schema || '"."' || routine_name || '"'  as full_name 
        from information_schema.routines  where routine_schema='public' 
            and data_type = 'trigger' and routine_name not in ('postgis_cache_bbox', 'checkauthtrigger', 'f_for_trg_track_history', 'f_for_trg_track_changes')
  LOOP
      EXECUTE 'DROP FUNCTION IF EXISTS '  || rec.full_name || '() CASCADE;';    
  END LOOP;
  RETURN 1; 
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.clean_db(
 schema_name varchar
) IS 'This function will delete any table and function in a schema that does not belong to the standard postgis template.';
    
-- Function public.compare_strings --
CREATE OR REPLACE FUNCTION public.compare_strings(
 string1 varchar
  , string2 varchar
) RETURNS bool 
AS $$
  BEGIN
    return string1 ilike '%' || string2 || '%';
  END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.compare_strings(
 string1 varchar
  , string2 varchar
) IS 'Special string compare function.';
    
-- Function public.get_geometry_with_srid --
CREATE OR REPLACE FUNCTION public.get_geometry_with_srid(
 geom geometry
) RETURNS geometry 
AS $$
BEGIN
  return st_setsrid(geom, coalesce((select vl::integer from system.setting where name='map-srid'),-1));
END;

$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.get_geometry_with_srid(
 geom geometry
) IS 'This function assigns a srid found in the settings to the geometry passed as parameter.';
    
-- Function public.get_translation --
CREATE OR REPLACE FUNCTION public.get_translation(
 mixed_value varchar
  , language_code varchar
) RETURNS varchar 
AS $$
DECLARE
  delimiter_word varchar;
  language_index integer;
  result varchar;
BEGIN
  if mixed_value is null then
    return mixed_value;
  end if;
  delimiter_word = '::::';
  language_index = (select item_order from system.language where code=language_code);
  result = split_part(mixed_value, delimiter_word, language_index);
  if result is null or result = '' then
    language_index = (select item_order from system.language where is_default limit 1);
    result = split_part(mixed_value, delimiter_word, language_index);
    if result is null or result = '' then
      result = mixed_value;
    end if;
  end if;
  return result;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.get_translation(
 mixed_value varchar
  , language_code varchar
) IS 'This function is used to translate the values that are supposed to be multilingual like the reference data values (display_value)';
    
-- Function public.clean_db_foreign_constraints --
CREATE OR REPLACE FUNCTION public.clean_db_foreign_constraints(

) RETURNS void 
AS $$
declare
  rec record;
begin
  for rec in select * from information_schema.table_constraints where constraint_type = 'FOREIGN KEY' loop
    execute 'ALTER TABLE "' || rec.table_schema || '"."' ||  rec.table_name || '" DROP CONSTRAINT "' || rec.constraint_name || '"'; 
    execute 'DROP INDEX IF EXISTS ' || rec.constraint_name || '_ind';
  end loop;
end;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.clean_db_foreign_constraints(

) IS 'This function can be used to drop all foreign key constraints from the database.';
    
-- Function public.clean_db_triggers --
CREATE OR REPLACE FUNCTION public.clean_db_triggers(

) RETURNS void 
AS $$
declare
  rec record;
begin
  for rec in SELECT distinct event_object_schema, event_object_table, trigger_name FROM information_schema.triggers 
    where trigger_name not in ('__track_changes', '__track_history') loop
    execute 'DROP TRIGGER "' || rec.trigger_name || '" ON "' || rec.event_object_schema || '"."' ||  rec.event_object_table || '" CASCADE;'; 
  end loop;
  for rec in select '"' || routine_schema || '"."' || routine_name || '"'  as full_name 
        from information_schema.routines  where routine_schema='public' 
            and data_type = 'trigger' and routine_name not in ('postgis_cache_bbox', 'checkauthtrigger', 'f_for_trg_track_history', 'f_for_trg_track_changes' )
  loop
      execute 'DROP FUNCTION IF EXISTS '  || rec.full_name || '() CASCADE;';
  end loop;
end;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION public.clean_db_triggers(

) IS 'This function removes all triggers and their related functions in the database. It assumes that the trigger functions are found in the public schema.';
    
-- Function party.is_rightholder --
CREATE OR REPLACE FUNCTION party.is_rightholder(
 id varchar
) RETURNS boolean 
AS $$
BEGIN
  return (SELECT (CASE (SELECT COUNT(1) FROM administrative.party_for_rrr ap WHERE ap.party_id = id) WHEN 0 THEN false ELSE true END));
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION party.is_rightholder(
 id varchar
) IS 'Gets if a party is rightholder.';
    
-- Function system.setPassword --
CREATE OR REPLACE FUNCTION system.setPassword(
 usrName varchar
  , pass varchar
) RETURNS int 
AS $$
DECLARE
  result int;
BEGIN
  update system.appuser set passwd = pass where username=usrName;
  GET DIAGNOSTICS result = ROW_COUNT;
  return result;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION system.setPassword(
 usrName varchar
  , pass varchar
) IS 'This function changes the password of the user.';
    
-- Function system.get_setting --
CREATE OR REPLACE FUNCTION system.get_setting(
 setting_name varchar
) RETURNS varchar 
AS $$
begin
  return (select vl from system.setting where name= setting_name);
end;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION system.get_setting(
 setting_name varchar
) IS 'Gets the value of a setting.';
    
-- Sequence application.application_nr_seq --
DROP SEQUENCE IF EXISTS application.application_nr_seq;
CREATE SEQUENCE application.application_nr_seq
INCREMENT 1
MINVALUE 1
MAXVALUE 9999
START 1
CACHE 1
CYCLE;
COMMENT ON SEQUENCE application.application_nr_seq IS 'Allocates numbers 1 to 9999 for application number';
    
-- Function application.getlodgement --
CREATE OR REPLACE FUNCTION application.getlodgement(
 fromdate varchar
  , todate varchar
) RETURNS SETOF record 
AS $$
DECLARE 
    resultType  varchar;
    resultGroup varchar;
    resultTotal integer :=0 ;
    resultTotalPerc decimal:=0 ;
    resultDailyAvg  decimal:=0 ;
    resultTotalReq integer:=0 ;
    resultReqPerc  decimal:=0 ;
    TotalTot integer:=0 ;
    appoDiff integer:=0 ;
    rec     record;
    sqlSt varchar;
    lodgementFound boolean;
    recToReturn record;

    
BEGIN  
    appoDiff := (to_date(''|| toDate || '','yyyy-mm-dd') - to_date(''|| fromDate || '','yyyy-mm-dd'));
     if  appoDiff= 0 then 
            appoDiff:= 1;
     end if; 
    sqlSt:= '';
    
    sqlSt:= 'select   1 as order,
         get_translation(application.request_type.display_value, null) as type,
         application.request_type.request_category_code as group,
         count(application.service_historic.id) as total,
         round((CAST(count(application.service_historic.id) as decimal)
         /
         '||appoDiff||'
         ),2) as dailyaverage
from     application.service_historic,
         application.request_type
where    application.service_historic.request_type_code = application.request_type.code
         and
         application.service_historic.lodging_datetime between to_date('''|| fromDate || ''',''yyyy-mm-dd'')  and to_date('''|| toDate || ''',''yyyy-mm-dd'')
         and application.service_historic.action_code=''lodge''
         and application.service_historic.application_id in
	      (select distinct(application.application_historic.id)
	       from application.application_historic)
group by application.service_historic.request_type_code, application.request_type.display_value,
         application.request_type.request_category_code
union
select   2 as order,
         ''Total'' as type,
         ''All'' as group,
         count(application.service_historic.id) as total,
         round((CAST(count(application.service_historic.id) as decimal)
         /
         '||appoDiff||'
         ),2) as dailyaverage
from     application.service_historic,
         application.request_type
where    application.service_historic.request_type_code = application.request_type.code
         and
         application.service_historic.lodging_datetime between to_date('''|| fromDate || ''',''yyyy-mm-dd'')  and to_date('''|| toDate || ''',''yyyy-mm-dd'')
         and application.service_historic.application_id in
	      (select distinct(application.application_historic.id)
	       from application.application_historic)
order by 1,3,2;
';




  

    --raise exception '%',sqlSt;
    lodgementFound = false;
    -- Loop through results
         select   
         count(application.service_historic.id)
         into TotalTot
from     application.service_historic,
         application.request_type
where    application.service_historic.request_type_code = application.request_type.code
         and
         application.service_historic.lodging_datetime between to_date(''|| fromDate || '','yyyy-mm-dd')  and to_date(''|| toDate || '','yyyy-mm-dd')
         and application.service_historic.application_id in
	      (select distinct(application.application_historic.id)
	       from application.application_historic);

    
    FOR rec in EXECUTE sqlSt loop
            resultType:= rec.type;
	    resultGroup:= rec.group;
	    resultTotal:= rec.total;
	    if  TotalTot= 0 then 
               TotalTot:= 1;
            end if; 
	    resultTotalPerc:= round((CAST(rec.total as decimal)*100/TotalTot),2);
	    resultDailyAvg:= rec.dailyaverage;
            resultTotalReq:= 0;

           

            if rec.type = 'Total' then
                 select   count(application.service_historic.id) into resultTotalReq
		from application.service_historic
		where application.service_historic.action_code='lodge'
                      and
                      application.service_historic.lodging_datetime between to_date(''|| fromDate || '','yyyy-mm-dd')  and to_date(''|| toDate || '','yyyy-mm-dd')
                      and application.service_historic.application_id in
		      (select application.application_historic.id
		       from application.application_historic
		       where application.application_historic.action_code='requisition');
            else
                  select  count(application.service_historic.id) into resultTotalReq
		from application.service_historic
		where application.service_historic.action_code='lodge'
                      and
                      application.service_historic.lodging_datetime between to_date(''|| fromDate || '','yyyy-mm-dd')  and to_date(''|| toDate || '','yyyy-mm-dd')
                      and application.service_historic.application_id in
		      (select application.application_historic.id
		       from application.application_historic
		       where application.application_historic.action_code='requisition'
		      )   
		and   application.service_historic.request_type_code = rec.type     
		group by application.service_historic.request_type_code;
            end if;

             if  rec.total= 0 then 
               appoDiff:= 1;
             else
               appoDiff:= rec.total;
             end if; 
            resultReqPerc:= round((CAST(resultTotalReq as decimal)*100/appoDiff),2);

            if resultType is null then
              resultType :=0 ;
            end if;
	    if resultTotal is null then
              resultTotal  :=0 ;
            end if;  
	    if resultTotalPerc is null then
	         resultTotalPerc  :=0 ;
            end if;  
	    if resultDailyAvg is null then
	        resultDailyAvg  :=0 ;
            end if;  
	    if resultTotalReq is null then
	        resultTotalReq  :=0 ;
            end if;  
	    if resultReqPerc is null then
	        resultReqPerc  :=0 ;
            end if;  

	    if TotalTot is null then
	       TotalTot  :=0 ;
            end if;  
	  
          select into recToReturn resultType::varchar, resultGroup::varchar, resultTotal::integer, resultTotalPerc::decimal,resultDailyAvg::decimal,resultTotalReq::integer,resultReqPerc::decimal;
          return next recToReturn;
          lodgementFound = true;
    end loop;
   
    if (not lodgementFound) then
        RAISE EXCEPTION 'no_lodgement_found';
    end if;
    return;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION application.getlodgement(
 fromdate varchar
  , todate varchar
) IS '';
    
-- Function application.getlodgetiming --
CREATE OR REPLACE FUNCTION application.getlodgetiming(
 fromdate date
  , todate date
) RETURNS SETOF record 
AS $$
DECLARE 
    timeDiff integer:=0 ;
BEGIN
timeDiff := toDate-fromDate;
if timeDiff<=0 then 
    timeDiff:= 1;
end if; 

return query
select 'Lodged not completed'::varchar as resultCode, count(1)::integer as resultTotal, (round(count(1)::numeric/timeDiff,1))::float as resultDailyAvg, 1 as ord 
from application.application
where lodging_datetime between fromdate and todate and status_code = 'lodged'
union
select 'Registered' as resultCode, count(1)::integer as resultTotal, (round(count(1)::numeric/timeDiff,1))::float as resultDailyAvg, 2 as ord 
from application.application
where lodging_datetime between fromdate and todate
union
select 'Rejected' as resultCode, count(1)::integer as resultTotal, (round(count(1)::numeric/timeDiff,1))::float as resultDailyAvg, 3 as ord 
from application.application
where lodging_datetime between fromdate and todate and status_code = 'annuled'
union
select 'On Requisition' as resultCode, count(1)::integer as resultTotal, (round(count(1)::numeric/timeDiff,1))::float as resultDailyAvg, 4 as ord 
from application.application
where lodging_datetime between fromdate and todate and status_code = 'requisitioned'
union
select 'Withdrawn' as resultCode, count(distinct id)::integer as resultTotal, (round(count(distinct id)::numeric/timeDiff,1))::float as resultDailyAvg, 5 as ord 
from application.application_historic
where change_time between fromdate and todate and action_code = 'withdraw'
order by ord;

END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION application.getlodgetiming(
 fromdate date
  , todate date
) IS '';
    
-- Function application.application_is_in_progress --
CREATE OR REPLACE FUNCTION application.application_is_in_progress(
 application_id_vl varchar
) RETURNS boolean 
AS $$
begin
  return (exists (select 1 
  from application.application_status s 
    inner join application.application_status_type st on s.type_code= st.code 
  where s.application_id = application_id_vl and s.is_current and not st.is_terminal));
end;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION application.application_is_in_progress(
 application_id_vl varchar
) IS 'It gives if an application is in progress or not.';
    
-- Function application.application_assigned_to --
CREATE OR REPLACE FUNCTION application.application_assigned_to(
 assigned_to_code varchar
  , assignee_id_vl varchar
  , username_vl varchar
) RETURNS boolean 
AS $$
begin
  if assigned_to_code = 'Everybody' then
    return true;
  elsif assigned_to_code = 'Me' then
    return coalesce(((select username from system.appuser where id = assignee_id_vl) = username_vl), false);
  elsif assigned_to_code = 'Office' then
    return coalesce(((select office_code from system.appuser where id = assignee_id_vl) = (select office_code from system.appuser where username = username_vl)), false);
  end if;
  return true;
end;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION application.application_assigned_to(
 assigned_to_code varchar
  , assignee_id_vl varchar
  , username_vl varchar
) IS '';
    
-- Function application.get_application_parties --
CREATE OR REPLACE FUNCTION application.get_application_parties(
 application_id_vl varchar
  , show_role bool
) RETURNS varchar 
AS $$
begin
  if show_role then
    return 
      (SELECT string_agg((COALESCE(p.name, '') || ' ') || COALESCE(p.last_name, '') || ' (' || p_r.display_value || ')', ', ') AS full_name
       FROM party.party p
        INNER JOIN application.application_party a_p ON a_p.party_id = p.id
        INNER JOIN party.party_role_type p_r on a_p.role_code = p_r.code
       WHERE a_p.application_id = application_id_vl);
  else
    return 
     (SELECT string_agg((COALESCE(p.name, '') || ' ') || COALESCE(p.last_name, ''), ', ') AS full_name
      FROM party.party p
        INNER JOIN application.application_party a_p ON a_p.party_id = p.id
      WHERE a_p.application_id = application_id_vl);
  end if;
end;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION application.get_application_parties(
 application_id_vl varchar
  , show_role bool
) IS 'It retrieves the parties seperated by commas that are involved in an application.';
    
-- Sequence source.source_la_nr_seq --
DROP SEQUENCE IF EXISTS source.source_la_nr_seq;
CREATE SEQUENCE source.source_la_nr_seq
INCREMENT 1
MINVALUE 1
MAXVALUE 999999999
START 1
CACHE 1
CYCLE;
COMMENT ON SEQUENCE source.source_la_nr_seq IS 'Allocates numbers 1 to 999999999 for source la number.';
    
-- Sequence document.document_nr_seq --
DROP SEQUENCE IF EXISTS document.document_nr_seq;
CREATE SEQUENCE document.document_nr_seq
INCREMENT 1
MINVALUE 1
MAXVALUE 9999
START 1
CACHE 1
CYCLE;
COMMENT ON SEQUENCE document.document_nr_seq IS 'Allocates numbers 1 to 9999 for document number.';
    
-- Sequence administrative.rrr_nr_seq --
DROP SEQUENCE IF EXISTS administrative.rrr_nr_seq;
CREATE SEQUENCE administrative.rrr_nr_seq
INCREMENT 1
MINVALUE 1
MAXVALUE 9999
START 1
CACHE 1
CYCLE;
COMMENT ON SEQUENCE administrative.rrr_nr_seq IS 'Allocates numbers 1 to 9999 for rrr number';
    
-- Sequence administrative.notation_reference_nr_seq --
DROP SEQUENCE IF EXISTS administrative.notation_reference_nr_seq;
CREATE SEQUENCE administrative.notation_reference_nr_seq
INCREMENT 1
MINVALUE 1
MAXVALUE 9999
START 1
CACHE 1
CYCLE;
COMMENT ON SEQUENCE administrative.notation_reference_nr_seq IS 'Allocates numbers 1 to 9999 for reference number for notation.';
    
-- Sequence administrative.ba_unit_first_name_part_seq --
DROP SEQUENCE IF EXISTS administrative.ba_unit_first_name_part_seq;
CREATE SEQUENCE administrative.ba_unit_first_name_part_seq
  INCREMENT 1
  MINVALUE 1
  MAXVALUE 9999
  START 1
  CACHE 1
  CYCLE;
COMMENT ON SEQUENCE administrative.ba_unit_first_name_part_seq IS 'Allocates numbers 1 to 9999 for ba unit first name part.';
    
-- Sequence administrative.ba_unit_last_name_part_seq --
DROP SEQUENCE IF EXISTS administrative.ba_unit_last_name_part_seq;
CREATE SEQUENCE administrative.ba_unit_last_name_part_seq
  INCREMENT 1
  MINVALUE 1
  MAXVALUE 9999
  START 1
  CACHE 1
  CYCLE;
COMMENT ON SEQUENCE administrative.ba_unit_last_name_part_seq IS 'Allocates numbers 1 to 9999 for ba unit last name part.';
    
-- Function administrative.get_ba_unit_pending_action --
CREATE OR REPLACE FUNCTION administrative.get_ba_unit_pending_action(
 baunit_id varchar
) RETURNS varchar 
AS $$
BEGIN
  return (SELECT rt.type_action_code
  FROM ((administrative.ba_unit_target bt INNER JOIN transaction.transaction t ON bt.transaction_id = t.id)
  INNER JOIN application.service s ON t.from_service_id = s.id)
  INNER JOIN application.request_type rt ON s.request_type_code = rt.code
  WHERE bt.ba_unit_id = baunit_id AND t.status_code = 'pending'
  LIMIT 1);
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION administrative.get_ba_unit_pending_action(
 baunit_id varchar
) IS 'It returns the action that must be taken in the pending ba_unit.';
    
-- Function administrative.ba_unit_name_is_valid --
CREATE OR REPLACE FUNCTION administrative.ba_unit_name_is_valid(
 name_firstpart varchar
  , name_lastpart varchar
) RETURNS boolean 
AS $$
begin
  if name_firstpart is null then return false; end if;
  if name_lastpart is null then return false; end if;
  if name_firstpart not like 'N%' then return false; end if;
  if name_lastpart not similar to '[0-9]+' then return false; end if;
  return true;
end;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION administrative.ba_unit_name_is_valid(
 name_firstpart varchar
  , name_lastpart varchar
) IS 'This function, checks if the name parts of the ba unit are valid.';
    
-- Function cadastre.cadastre_object_name_is_valid --
CREATE OR REPLACE FUNCTION cadastre.cadastre_object_name_is_valid(
 name_firstpart varchar
  , name_lastpart varchar
) RETURNS boolean 
AS $$
begin
  if name_firstpart is null then return false; end if;
  if name_lastpart is null then return false; end if;
  if not (name_firstpart similar to 'Lot [0-9]+' or name_firstpart similar to '[0-9]+') then return false;  end if;
  if name_lastpart not similar to '(D|S)P [0-9 ]+' then return false;  end if;
  return true;
end;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION cadastre.cadastre_object_name_is_valid(
 name_firstpart varchar
  , name_lastpart varchar
) IS 'This function, checks if the name parts of the cadastre_object are valid.';
    
-- Function cadastre.add_topo_points --
CREATE OR REPLACE FUNCTION cadastre.add_topo_points(
 source geometry
  , target geometry
) RETURNS geometry 
AS $$
declare
  rec record;
  point_location float;
  point_to_add geometry;
  rings geometry[];
  nr_elements integer;
  tolerance double precision;
  i integer;
begin
  tolerance = system.get_setting('map-tolerance')::double precision;
  if st_geometrytype(target) = 'ST_LineString' then
    for rec in 
      select geom from St_DumpPoints(source) s
        where st_dwithin(target, s.geom, tolerance)
    loop
      if (select count(1) from st_dumppoints(target) t where st_dwithin(rec.geom, t.geom, tolerance))=0 then
        point_location = ST_Line_Locate_Point(target, rec.geom);
        --point_to_add = ST_Line_Interpolate_Point(target, point_location);
        target = ST_LineMerge(ST_Union(ST_Line_Substring(target, 0, point_location), ST_Line_Substring(target, point_location, 1)));
      end if;
    end loop;
  elsif st_geometrytype(target)= 'ST_Polygon' then
    select  array_agg(ST_ExteriorRing(geom)) into rings from ST_DumpRings(target);
    nr_elements = array_upper(rings, 1);
    for i in 1..nr_elements loop
      rings[i] = cadastre.add_topo_points(source, rings[i]);
    end loop;
    target = ST_MakePolygon(rings[1], rings[2:nr_elements]);
  end if;
  return target;
end;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION cadastre.add_topo_points(
 source geometry
  , target geometry
) IS 'This function searches for any point in source that falls into target. If a point is found then the point it is added in the target.
It returns the modified target.';
    
-- Function cadastre.get_first_part --
CREATE OR REPLACE FUNCTION cadastre.get_first_part(
 type varchar
  , the_geom_v geometry
) RETURNS varchar 
AS $$
declare
  where_is_found varchar;
  point_on_surface geometry;
begin
  point_on_surface = get_geometry_with_srid(ST_PointOnSurface(the_geom_v));
  
  if type = 'parcel' then
    where_is_found = (select id from cadastre.block 
      where the_geom && point_on_surface and st_intersects(the_geom, point_on_surface));
  elsif type = 'allodial' then
    where_is_found = (select id from cadastre.region 
      where the_geom && point_on_surface and st_intersects(the_geom, point_on_surface));    
  elsif type = 'building' then
    where_is_found = (select name_firstpart || '/' || name_lastpart from cadastre.cadastre_object 
      where status_code = 'current' and type_code= 'parcel'  and 
      geom_polygon && point_on_surface and st_intersects(geom_polygon, point_on_surface ));    
  elsif type = 'strata' then
    where_is_found = (select name_firstpart || '/' || name_lastpart from cadastre.cadastre_object 
      where status_code = 'current' and type_code= 'building'  and 
      geom_polygon && point_on_surface and st_intersects(geom_polygon, point_on_surface ));    
  end if;
  return coalesce(where_is_found, 'unkown');
end;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION cadastre.get_first_part(
 type varchar
  , the_geom_v geometry
) IS '';
    
-- Function cadastre.get_last_part --
CREATE OR REPLACE FUNCTION cadastre.get_last_part(
 first_part_v varchar
) RETURNS varchar 
AS $$
begin
  return (select coalesce(max(name_lastpart::integer),0)+1 from cadastre.cadastre_object where name_firstpart = first_part_v);
end;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION cadastre.get_last_part(
 first_part_v varchar
) IS '';
    
-- Function cadastre.snap_geometry_to_geometry --
CREATE OR REPLACE FUNCTION cadastre.snap_geometry_to_geometry(
inout geom_to_snap geometry
  ,inout target_geom geometry
  , snap_distance double precision
  , change_target_if_needed bool
  ,out snapped bool
  ,out target_is_changed bool
) RETURNS record 
AS $$
DECLARE
  i integer;
  nr_elements integer;
  rec record;
  rec2 record;
  point_location float;
  rings geometry[];
  
BEGIN
  target_is_changed = false;
  snapped = false;
  if st_geometrytype(geom_to_snap) not in ('ST_Point', 'ST_LineString', 'ST_Polygon') then
    raise exception 'geom_to_snap not supported. Only point, linestring and polygon is supported.';
  end if;
  if st_geometrytype(geom_to_snap) = 'ST_Point' then
    -- If the geometry to snap is POINT
    if st_geometrytype(target_geom) = 'ST_Point' then
      if st_dwithin(geom_to_snap, target_geom, snap_distance) then
        geom_to_snap = target_geom;
        snapped = true;
      end if;
    elseif st_geometrytype(target_geom) = 'ST_LineString' then
      -- Check first if there is any point of linestring where the point can be snapped.
      select t.* into rec from ST_DumpPoints(target_geom) t where st_dwithin(geom_to_snap, t.geom, snap_distance);
      if rec is not null then
        geom_to_snap = rec.geom;
        snapped = true;
        return;
      end if;
      --Check second if the point is within distance from linestring and get an interpolation point in the line.
      if st_dwithin(geom_to_snap, target_geom, snap_distance) then
        point_location = ST_Line_Locate_Point(target_geom, geom_to_snap);
        geom_to_snap = ST_Line_Interpolate_Point(target_geom, point_location);
        if change_target_if_needed then
          target_geom = ST_LineMerge(ST_Union(ST_Line_Substring(target_geom, 0, point_location), ST_Line_Substring(target_geom, point_location, 1)));
          target_is_changed = true;
        end if;
        snapped = true;  
      end if;
    elseif st_geometrytype(target_geom) = 'ST_Polygon' then
      select  array_agg(ST_ExteriorRing(geom)) into rings from ST_DumpRings(target_geom);
      nr_elements = array_upper(rings,1);
      i = 1;
      while i <= nr_elements loop
        select t.* into rec from cadastre.snap_geometry_to_geometry(geom_to_snap, rings[i], snap_distance, change_target_if_needed) t;
        if rec.snapped then
          geom_to_snap = rec.geom_to_snap;
          snapped = true;
          if change_target_if_needed then
            rings[i] = rec.target_geom;
            target_geom = ST_MakePolygon(rings[1], rings[2:nr_elements]);
            target_is_changed = rec.target_is_changed;
            return;
          end if;
        end if;
        i = i+1;
      end loop;
    end if;
  elseif st_geometrytype(geom_to_snap) = 'ST_LineString' then
    nr_elements = st_npoints(geom_to_snap);
    i = 1;
    while i <= nr_elements loop
      select t.* into rec
        from cadastre.snap_geometry_to_geometry(st_pointn(geom_to_snap,i), target_geom, snap_distance, change_target_if_needed) t;
      if rec.snapped then
        if rec.target_is_changed then
          target_geom= rec.target_geom;
          target_is_changed = true;
        end if;
        geom_to_snap = st_setpoint(geom_to_snap, i-1, rec.geom_to_snap);
        snapped = true;
      end if;
      i = i+1;
    end loop;
    -- For each point of the target checks if it can snap to the geom_to_snap
    for rec in select * from ST_DumpPoints(target_geom) t 
      where st_dwithin(geom_to_snap, t.geom, snap_distance) loop
      select t.* into rec2
        from cadastre.snap_geometry_to_geometry(rec.geom, geom_to_snap, snap_distance, true) t;
      if rec2.target_is_changed then
        geom_to_snap = rec2.target_geom;
        snapped = true;
      end if;
    end loop;
  elseif st_geometrytype(geom_to_snap) = 'ST_Polygon' then
    select  array_agg(ST_ExteriorRing(geom)) into rings from ST_DumpRings(geom_to_snap);
    nr_elements = array_upper(rings,1);
    i = 1;
    while i <= nr_elements loop
      select t.* into rec
        from cadastre.snap_geometry_to_geometry(rings[i], target_geom, snap_distance, change_target_if_needed) t;
      if rec.snapped then
        rings[i] = rec.geom_to_snap;
        if rec.target_is_changed then
          target_geom = rec.target_geom;
          target_is_changed = true;
        end if;
        snapped = true;
      end if;
      i= i+1;
    end loop;
    if snapped then
      geom_to_snap = ST_MakePolygon(rings[1], rings[2:nr_elements]);
    end if;
  end if;
  return;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION cadastre.snap_geometry_to_geometry(
inout geom_to_snap geometry
  ,inout target_geom geometry
  , snap_distance double precision
  , change_target_if_needed bool
  ,out snapped bool
  ,out target_is_changed bool
) IS 'It snaps one geometry to the other. If points needs to be added they will be added.';
    
-- Function cadastre.get_app_regional_number --
CREATE OR REPLACE FUNCTION cadastre.get_app_regional_number(

) RETURNS varchar 
AS $$
declare
  region_code varchar;
  latest_number integer;
  latest_char varchar;
  latest_year varchar;
begin
  region_code = system.get_setting('current-region');
  latest_char = (select coalesce(app_regnr_counter, 'A000') from cadastre.region where code = region_code);
  latest_number = substring(latest_char from 2 for 3)::integer;
  latest_char = substring(latest_char from 1 for 1);
  latest_year = (select coalesce(app_regnr_counter_year, extract('year' from now())::varchar) from cadastre.region where code = region_code);
  if latest_year != extract('year' from now())::varchar then
    latest_year = extract('year' from now())::varchar;
    latest_number = 1;
    latest_char = 'A';
  elsif latest_number = 999 then
    latest_char = chr(ascii(latest_char) + 1)::varchar;
    latest_number = 1;
  else
    latest_number = latest_number+1;
  end if;
  update cadastre.region set app_regnr_counter = latest_char || lpad(latest_number::varchar, 3, '0'), app_regnr_counter_year = latest_year where code = region_code;
  return 'SG/' || region_code || '/' || latest_char || lpad(latest_number::varchar, 3, '0') || '/' || substring(latest_year from 3);
end;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION cadastre.get_app_regional_number(

) IS 'It generates the next regional number for the applications of the surveyors for regional numbers.';
    
    
select clean_db('public');
    
    
--Table source.source ----
DROP TABLE IF EXISTS source.source CASCADE;
CREATE TABLE source.source(
    id varchar(40) NOT NULL,
    maintype varchar(20),
    la_nr varchar(20) NOT NULL,
    reference_nr varchar(20),
    archive_id varchar(40),
    acceptance date,
    recordation date,
    submission date DEFAULT (now()),
    expiration_date date,
    commencement_date date,
    ext_archive_id varchar(40),
    availability_status_code varchar(20) NOT NULL DEFAULT ('available'),
    type_code varchar(20) NOT NULL,
    content varchar(4000),
    status_code varchar(20),
    transaction_id varchar(40),
    owner_name varchar(255),
    version varchar(10),
    description varchar(255),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT source_pkey PRIMARY KEY (id)
);



-- Index source_index_on_rowidentifier  --
CREATE INDEX source_index_on_rowidentifier ON source.source (rowidentifier);
    

comment on table source.source is 'Documents or recognised facts providing the basis for the recording of a registration, cadastre change, right, responsibility or administrative action performed by the land office
LADM Reference Object 
LA_Source
LADM Definition
Not defined';
    
DROP TRIGGER IF EXISTS __track_changes ON source.source CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON source.source FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table source.source_historic used for the history of data of table source.source ---
DROP TABLE IF EXISTS source.source_historic CASCADE;
CREATE TABLE source.source_historic
(
    id varchar(40),
    maintype varchar(20),
    la_nr varchar(20),
    reference_nr varchar(20),
    archive_id varchar(40),
    acceptance date,
    recordation date,
    submission date,
    expiration_date date,
    commencement_date date,
    ext_archive_id varchar(40),
    availability_status_code varchar(20),
    type_code varchar(20),
    content varchar(4000),
    status_code varchar(20),
    transaction_id varchar(40),
    owner_name varchar(255),
    version varchar(10),
    description varchar(255),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index source_historic_index_on_rowidentifier  --
CREATE INDEX source_historic_index_on_rowidentifier ON source.source_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON source.source CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON source.source FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table source.availability_status_type ----
DROP TABLE IF EXISTS source.availability_status_type CASCADE;
CREATE TABLE source.availability_status_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL DEFAULT ('c'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT availability_status_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT availability_status_type_pkey PRIMARY KEY (code)
);


comment on table source.availability_status_type is 'Reference Table / Code list of source (document) availability status type
LADM Reference Object 
LA_AvailabilityStatusType
LADM Definition
Not Defined';
    
 -- Data for the table source.availability_status_type -- 
insert into source.availability_status_type(code, display_value, status) values('archiveConverted', 'Converted::::Convertito', 'c');
insert into source.availability_status_type(code, display_value, status) values('archiveDestroyed', 'Destroyed::::Distrutto', 'x');
insert into source.availability_status_type(code, display_value, status) values('incomplete', 'Incomplete::::Incompleto', 'c');
insert into source.availability_status_type(code, display_value, status) values('archiveUnknown', 'Unknown::::Sconosciuto', 'c');
insert into source.availability_status_type(code, display_value, status, description) values('available', 'Available', 'c', 'Extension to LADM');



--Table source.administrative_source_type ----
DROP TABLE IF EXISTS source.administrative_source_type CASCADE;
CREATE TABLE source.administrative_source_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL,
    is_for_registration bool NOT NULL DEFAULT (false),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT administrative_source_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT administrative_source_type_pkey PRIMARY KEY (code)
);


comment on table source.administrative_source_type is 'Reference Table / Code list of administrative source types
LADM Reference Object 
LA_AdministrativeSourceType
LADM Definition
Not Defined';
    
 -- Data for the table source.administrative_source_type -- 
insert into source.administrative_source_type(code, display_value, status, is_for_registration, description) values('idVerification', 'ID Card', 'c', false, 'Extension to LADM');
insert into source.administrative_source_type(code, display_value, status, is_for_registration) values('sitePlan', 'Site Plan', 'c', false);
insert into source.administrative_source_type(code, display_value, status, is_for_registration) values('reqFromSurveor', 'Request letter from Licensed Surveyor', 'c', false);



--Table source.spatial_source ----
DROP TABLE IF EXISTS source.spatial_source CASCADE;
CREATE TABLE source.spatial_source(
    id varchar(40) NOT NULL,
    procedure varchar(255),
    type_code varchar(20) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT spatial_source_pkey PRIMARY KEY (id)
);



-- Index spatial_source_index_on_rowidentifier  --
CREATE INDEX spatial_source_index_on_rowidentifier ON source.spatial_source (rowidentifier);
    

comment on table source.spatial_source is 'Refer to LADM Definition
LADM Reference Object 
LA_Source
LADM Definition 
A spatial source may be the final (sometimes formal) documents, or all documents related to a survey. Sometimes serveral documents are the result of a single survey. A spatial source may be official or not (ie a registered survey plan or an aerial photograph).';
    
DROP TRIGGER IF EXISTS __track_changes ON source.spatial_source CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON source.spatial_source FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table source.spatial_source_historic used for the history of data of table source.spatial_source ---
DROP TABLE IF EXISTS source.spatial_source_historic CASCADE;
CREATE TABLE source.spatial_source_historic
(
    id varchar(40),
    procedure varchar(255),
    type_code varchar(20),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index spatial_source_historic_index_on_rowidentifier  --
CREATE INDEX spatial_source_historic_index_on_rowidentifier ON source.spatial_source_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON source.spatial_source CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON source.spatial_source FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table source.spatial_source_type ----
DROP TABLE IF EXISTS source.spatial_source_type CASCADE;
CREATE TABLE source.spatial_source_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT spatial_source_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT spatial_source_type_pkey PRIMARY KEY (code)
);


comment on table source.spatial_source_type is 'Reference Table / Code list of spatial source type
LADM Reference Object 
LA_SpatialSourceType
LADM Definition
Type of Spatial Source';
    
 -- Data for the table source.spatial_source_type -- 
insert into source.spatial_source_type(code, display_value, status) values('fieldSketch', 'Field Sketch::::Schizzo Campo', 'c');
insert into source.spatial_source_type(code, display_value, status) values('gnssSurvey', 'GNSS (GPS) Survey::::Rilevamento GNSS (GPS)', 'c');
insert into source.spatial_source_type(code, display_value, status) values('orthoPhoto', 'Orthophoto::::Foto Ortopanoramica', 'c');
insert into source.spatial_source_type(code, display_value, status) values('relativeMeasurement', 'Relative Measurements::::Misure relativa', 'c');
insert into source.spatial_source_type(code, display_value, status) values('topoMap', 'Topographical Map::::Mappa Topografica', 'c');
insert into source.spatial_source_type(code, display_value, status) values('video', 'Video::::Video', 'c');
insert into source.spatial_source_type(code, display_value, status, description) values('cadastralSurvey', 'Cadastral Survey::::Perizia Catastale', 'c', 'Extension to LADM');



--Table source.spatial_source_measurement ----
DROP TABLE IF EXISTS source.spatial_source_measurement CASCADE;
CREATE TABLE source.spatial_source_measurement(
    spatial_source_id varchar(40) NOT NULL,
    id varchar(40) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT spatial_source_measurement_pkey PRIMARY KEY (spatial_source_id,id)
);



-- Index spatial_source_measurement_index_on_rowidentifier  --
CREATE INDEX spatial_source_measurement_index_on_rowidentifier ON source.spatial_source_measurement (rowidentifier);
    

comment on table source.spatial_source_measurement is 'Refer to LADM Definition
LADM Reference Object 
OM_Observation
LADM Definition
The observations, and measurements, as a basis for mapping, and as a basis for historical reconstruction of the location of (parts of) the spatial unit in the field';
    
DROP TRIGGER IF EXISTS __track_changes ON source.spatial_source_measurement CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON source.spatial_source_measurement FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table source.spatial_source_measurement_historic used for the history of data of table source.spatial_source_measurement ---
DROP TABLE IF EXISTS source.spatial_source_measurement_historic CASCADE;
CREATE TABLE source.spatial_source_measurement_historic
(
    spatial_source_id varchar(40),
    id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index spatial_source_measurement_historic_index_on_rowidentifier  --
CREATE INDEX spatial_source_measurement_historic_index_on_rowidentifier ON source.spatial_source_measurement_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON source.spatial_source_measurement CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON source.spatial_source_measurement FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table party.party ----
DROP TABLE IF EXISTS party.party CASCADE;
CREATE TABLE party.party(
    id varchar(40) NOT NULL,
    ext_id varchar(255),
    type_code varchar(20) NOT NULL,
    name varchar(255),
    last_name varchar(50),
    previous_name varchar(50),
    previous_last_name varchar(50),
    alias varchar(50),
    gender_code varchar(20),
    physical_address_id varchar(40),
    postal_address_id varchar(40),
    email varchar(50),
    mobile varchar(15),
    phone varchar(15),
    fax varchar(15),
    preferred_communication_code varchar(20),
    nationality_code varchar(20),
    dob_doi date,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT party_pkey PRIMARY KEY (id)
);



-- Index party_index_on_rowidentifier  --
CREATE INDEX party_index_on_rowidentifier ON party.party (rowidentifier);
    

comment on table party.party is 'An individual or group of individual people or a non-person organisation that is associated in some way with land office services.
Also refer to LADM Definition
LADM Reference Object 
LA_Party
LADM Definition
Registered and identified as a constituent of a group party.';
    
DROP TRIGGER IF EXISTS __track_changes ON party.party CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON party.party FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table party.party_historic used for the history of data of table party.party ---
DROP TABLE IF EXISTS party.party_historic CASCADE;
CREATE TABLE party.party_historic
(
    id varchar(40),
    ext_id varchar(255),
    type_code varchar(20),
    name varchar(255),
    last_name varchar(50),
    previous_name varchar(50),
    previous_last_name varchar(50),
    alias varchar(50),
    gender_code varchar(20),
    physical_address_id varchar(40),
    postal_address_id varchar(40),
    email varchar(50),
    mobile varchar(15),
    phone varchar(15),
    fax varchar(15),
    preferred_communication_code varchar(20),
    nationality_code varchar(20),
    dob_doi date,
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index party_historic_index_on_rowidentifier  --
CREATE INDEX party_historic_index_on_rowidentifier ON party.party_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON party.party CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON party.party FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table party.party_type ----
DROP TABLE IF EXISTS party.party_type CASCADE;
CREATE TABLE party.party_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT party_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT party_type_pkey PRIMARY KEY (code)
);


comment on table party.party_type is 'Reference Table / Code list of party types
LADM Reference Object 
LA_
LADM Definition
The type of party';
    
 -- Data for the table party.party_type -- 
insert into party.party_type(code, display_value, status) values('naturalPerson', 'Natural Person', 'c');
insert into party.party_type(code, display_value, status) values('nonNaturalPerson', 'Non-natural Person', 'c');



--Table party.group_party ----
DROP TABLE IF EXISTS party.group_party CASCADE;
CREATE TABLE party.group_party(
    id varchar(40) NOT NULL,
    type_code varchar(20) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT group_party_pkey PRIMARY KEY (id)
);



-- Index group_party_index_on_rowidentifier  --
CREATE INDEX group_party_index_on_rowidentifier ON party.group_party (rowidentifier);
    

comment on table party.group_party is 'Refer to LADM Definition
LADM Reference Object 
LA_GroupParty
LADM Definition
Any number of parties, forming together a distinct entity, with each party identified';
    
DROP TRIGGER IF EXISTS __track_changes ON party.group_party CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON party.group_party FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table party.group_party_historic used for the history of data of table party.group_party ---
DROP TABLE IF EXISTS party.group_party_historic CASCADE;
CREATE TABLE party.group_party_historic
(
    id varchar(40),
    type_code varchar(20),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index group_party_historic_index_on_rowidentifier  --
CREATE INDEX group_party_historic_index_on_rowidentifier ON party.group_party_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON party.group_party CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON party.group_party FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table party.group_party_type ----
DROP TABLE IF EXISTS party.group_party_type CASCADE;
CREATE TABLE party.group_party_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT group_party_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT group_party_type_pkey PRIMARY KEY (code)
);


comment on table party.group_party_type is 'Reference Table / Code list to identify different types of groups being a party to some form of land office transaction
LADM Reference Object 
LA_
LADM Definition
Not Defined';
    
 -- Data for the table party.group_party_type -- 
insert into party.group_party_type(code, display_value, status) values('tribe', 'Tribe::::Tribu', 'x');
insert into party.group_party_type(code, display_value, status) values('association', 'Association::::Associazione', 'c');
insert into party.group_party_type(code, display_value, status) values('family', 'Family::::Famiglia', 'c');
insert into party.group_party_type(code, display_value, status) values('baunitGroup', 'Basic Administrative Unit Group::::Unita Gruppo Amministrativo di Base', 'x');



--Table party.party_member ----
DROP TABLE IF EXISTS party.party_member CASCADE;
CREATE TABLE party.party_member(
    party_id varchar(40) NOT NULL,
    group_id varchar(40) NOT NULL,
    share double precision,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT party_member_pkey PRIMARY KEY (party_id,group_id)
);



-- Index party_member_index_on_rowidentifier  --
CREATE INDEX party_member_index_on_rowidentifier ON party.party_member (rowidentifier);
    

comment on table party.party_member is 'Refer to LADM Definition
LADM Reference Object 
LA_PartyMember
LADM Definition
A member belonging to a party.';
    
DROP TRIGGER IF EXISTS __track_changes ON party.party_member CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON party.party_member FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table party.party_member_historic used for the history of data of table party.party_member ---
DROP TABLE IF EXISTS party.party_member_historic CASCADE;
CREATE TABLE party.party_member_historic
(
    party_id varchar(40),
    group_id varchar(40),
    share double precision,
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index party_member_historic_index_on_rowidentifier  --
CREATE INDEX party_member_historic_index_on_rowidentifier ON party.party_member_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON party.party_member CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON party.party_member FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table administrative.ba_unit ----
DROP TABLE IF EXISTS administrative.ba_unit CASCADE;
CREATE TABLE administrative.ba_unit(
    id varchar(40) NOT NULL,
    type_code varchar(20) NOT NULL,
    name varchar(255),
    name_firstpart varchar(20) NOT NULL,
    name_lastpart varchar(50) NOT NULL,
    status_code varchar(20) NOT NULL,
    transaction_id varchar(40),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT ba_unit_pkey PRIMARY KEY (id)
);



-- Index ba_unit_index_on_rowidentifier  --
CREATE INDEX ba_unit_index_on_rowidentifier ON administrative.ba_unit (rowidentifier);
    

comment on table administrative.ba_unit is 'Refer to LADM Definition
LADM Reference Object 
LA_BAUnit
LADM Definition
Basic administrative units (abbreviated as baunits), are needed, among other things, to register ‘basic property units’, which consist of several spatial units, belonging to a party, under the same right (a right must be ''homogeneous'' over the whole baunit).
.';
    
DROP TRIGGER IF EXISTS __track_changes ON administrative.ba_unit CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON administrative.ba_unit FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table administrative.ba_unit_historic used for the history of data of table administrative.ba_unit ---
DROP TABLE IF EXISTS administrative.ba_unit_historic CASCADE;
CREATE TABLE administrative.ba_unit_historic
(
    id varchar(40),
    type_code varchar(20),
    name varchar(255),
    name_firstpart varchar(20),
    name_lastpart varchar(50),
    status_code varchar(20),
    transaction_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index ba_unit_historic_index_on_rowidentifier  --
CREATE INDEX ba_unit_historic_index_on_rowidentifier ON administrative.ba_unit_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON administrative.ba_unit CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON administrative.ba_unit FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table administrative.ba_unit_type ----
DROP TABLE IF EXISTS administrative.ba_unit_type CASCADE;
CREATE TABLE administrative.ba_unit_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('t'),

    -- Internal constraints
    
    CONSTRAINT ba_unit_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT ba_unit_type_pkey PRIMARY KEY (code)
);


comment on table administrative.ba_unit_type is 'Reference Table / Code list for types of BA Units
LADM Reference Object 
LA_BAUnitType
LADM Definition
Not Defined';
    
 -- Data for the table administrative.ba_unit_type -- 
insert into administrative.ba_unit_type(code, display_value, status) values('allodial', 'Allodial', 'c');
insert into administrative.ba_unit_type(code, display_value, status) values('customaryLawFreehold', 'Customary Law Freehold', 'c');
insert into administrative.ba_unit_type(code, display_value, status) values('leaseHold', 'Lease Hold', 'c');
insert into administrative.ba_unit_type(code, display_value, description, status) values('commonLawFreehold', 'Common Law Freehold', '', 'c');



--Table administrative.rrr ----
DROP TABLE IF EXISTS administrative.rrr CASCADE;
CREATE TABLE administrative.rrr(
    id varchar(40) NOT NULL,
    ba_unit_id varchar(40) NOT NULL,
    nr varchar(20) NOT NULL,
    type_code varchar(20) NOT NULL,
    status_code varchar(20) NOT NULL DEFAULT ('pending'),
    is_primary bool NOT NULL DEFAULT (false),
    transaction_id varchar(40) NOT NULL,
    registration_date timestamp,
    expiration_date timestamp,
    share double precision,
    mortgage_amount numeric(29, 2),
    mortgage_interest_rate numeric(5, 2),
    mortgage_ranking integer,
    mortgage_type_code varchar(20),
    mortgage_installment numeric(29, 2),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT rrr_pkey PRIMARY KEY (id)
);



-- Index rrr_index_on_rowidentifier  --
CREATE INDEX rrr_index_on_rowidentifier ON administrative.rrr (rowidentifier);
    

comment on table administrative.rrr is 'Refer to LADM Definition
LADM Reference Object 
LA_RRR
LADM Definition
A right, restriction or responsibility.';
    
DROP TRIGGER IF EXISTS __track_changes ON administrative.rrr CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON administrative.rrr FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table administrative.rrr_historic used for the history of data of table administrative.rrr ---
DROP TABLE IF EXISTS administrative.rrr_historic CASCADE;
CREATE TABLE administrative.rrr_historic
(
    id varchar(40),
    ba_unit_id varchar(40),
    nr varchar(20),
    type_code varchar(20),
    status_code varchar(20),
    is_primary bool,
    transaction_id varchar(40),
    registration_date timestamp,
    expiration_date timestamp,
    share double precision,
    mortgage_amount numeric(29, 2),
    mortgage_interest_rate numeric(5, 2),
    mortgage_ranking integer,
    mortgage_type_code varchar(20),
    mortgage_installment numeric(29, 2),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index rrr_historic_index_on_rowidentifier  --
CREATE INDEX rrr_historic_index_on_rowidentifier ON administrative.rrr_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON administrative.rrr CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON administrative.rrr FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table administrative.rrr_group_type ----
DROP TABLE IF EXISTS administrative.rrr_group_type CASCADE;
CREATE TABLE administrative.rrr_group_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT rrr_group_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT rrr_group_type_pkey PRIMARY KEY (code)
);


comment on table administrative.rrr_group_type is 'Reference Table / Code list for different categories of LA_RRR
LADM Reference Object 
LA_Responsibility, LA_Right, LA_Restriction as specialisations of LA_RR
LADM Definition
Not Defined';
    
 -- Data for the table administrative.rrr_group_type -- 
insert into administrative.rrr_group_type(code, display_value, status) values('rights', 'Rights::::Diritti', 'c');
insert into administrative.rrr_group_type(code, display_value, status) values('restrictions', 'Restrictions::::Restrizioni', 'c');
insert into administrative.rrr_group_type(code, display_value, status) values('responsibilities', 'Responsibilities::::Responsabilita', 'x');



--Table administrative.rrr_type ----
DROP TABLE IF EXISTS administrative.rrr_type CASCADE;
CREATE TABLE administrative.rrr_type(
    code varchar(20) NOT NULL,
    rrr_group_type_code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    is_primary bool NOT NULL DEFAULT (false),
    share_check bool NOT NULL,
    party_required bool NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('t'),

    -- Internal constraints
    
    CONSTRAINT rrr_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT rrr_type_pkey PRIMARY KEY (code)
);


comment on table administrative.rrr_type is 'Reference Table / Code list of rrr types
LADM Reference Object 
LA_RightType, LA_RestrictionType &
LA_ResponsibilityType
LADM Definition
The type of right/restriction/responsibility';
    
 -- Data for the table administrative.rrr_type -- 
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('agriActivity', 'rights', 'Agriculture Activity::::Attivita Agricola', false, true, true, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('commonOwnership', 'rights', 'Common Ownership::::Proprieta Comune', false, true, true, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('customaryType', 'rights', 'Customary Right::::Diritto Abituale', false, true, true, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('firewood', 'rights', 'Firewood Collection::::Collezione legna da ardere', false, true, true, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('fishing', 'rights', 'Fishing Right::::Diritto di Pesca', false, true, true, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('grazing', 'rights', 'Grazing Right::::Diritto di Pascolo', false, true, true, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('informalOccupation', 'rights', 'Informal Occupation::::Occupazione informale', false, false, false, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('lease', 'rights', 'Lease::::Affitto', false, true, true, 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('occupation', 'rights', 'Occupation::::Occupazione', false, true, true, 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('ownership', 'rights', 'Ownership::::Proprieta', true, true, true, 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('ownershipAssumed', 'rights', 'Ownership Assumed::::Proprieta Assunta', true, true, true, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('superficies', 'rights', 'Superficies::::Superficie', false, true, true, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('tenancy', 'rights', 'Tenancy::::Locazione', true, true, true, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('usufruct', 'rights', 'Usufruct::::Usufrutto', false, true, true, 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('waterrights', 'rights', 'Water Right::::Servitu di Acqua', false, true, true, 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('adminPublicServitude', 'restrictions', 'Administrative Public Servitude::::Servitu  Amministrazione Pubblica', false, true, true, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('monument', 'restrictions', 'Monument::::Monumento', false, true, true, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('mortgage', 'restrictions', 'Mortgage::::Ipoteca', false, true, true, 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('noBuilding', 'restrictions', 'Building Restriction::::Restrizione di Costruzione', false, false, false, 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('servitude', 'restrictions', 'Servitude::::Servitu', false, false, false, 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('monumentMaintenance', 'responsibilities', 'Monument Maintenance::::Mantenimento Monumenti', false, false, false, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('waterwayMaintenance', 'responsibilities', 'Waterway Maintenance::::Mantenimento Acqurdotti', false, false, false, 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, description, status) values('lifeEstate', 'rights', 'Life Estate::::Patrimonio vita', true, true, true, 'Extension to LADM', 'x');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, description, status) values('apartment', 'rights', 'Apartment Ownership::::Proprieta Appartamento', true, true, true, 'Extension to LADM', 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, description, status) values('stateOwnership', 'rights', 'State Ownership::::Proprieta di Stato', true, false, false, 'Extension to LADM', 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, description, status) values('caveat', 'restrictions', 'Caveat::::Ammonizione', false, true, true, 'Extension to LADM', 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, description, status) values('historicPreservation', 'restrictions', 'Historic Preservation::::Conservazione Storica', false, false, false, 'Extension to LADM', 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, description, status) values('limitedAccess', 'restrictions', 'Limited Access (to Road)::::Accesso limitato (su strada)', false, false, false, 'Extension to LADM', 'c');
insert into administrative.rrr_type(code, rrr_group_type_code, display_value, is_primary, share_check, party_required, status) values('rrrStandard', 'rights', 'Incidence of Interest', true, true, true, 'c');



--Table administrative.mortgage_type ----
DROP TABLE IF EXISTS administrative.mortgage_type CASCADE;
CREATE TABLE administrative.mortgage_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT mortgage_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT mortgage_type_pkey PRIMARY KEY (code)
);


comment on table administrative.mortgage_type is 'Reference Table / Code list for types of mortgage
LADM Reference Object 
LA_
LADM Definition
Not Defined';
    
 -- Data for the table administrative.mortgage_type -- 
insert into administrative.mortgage_type(code, display_value, status) values('levelPayment', 'Level Payment::::Livello Pagamento', 'c');
insert into administrative.mortgage_type(code, display_value, status) values('linear', 'Linear::::Lineare', 'c');
insert into administrative.mortgage_type(code, display_value, status) values('microCredit', 'Micro Credit::::Micro Credito', 'c');



--Table administrative.mortgage_isbased_in_rrr ----
DROP TABLE IF EXISTS administrative.mortgage_isbased_in_rrr CASCADE;
CREATE TABLE administrative.mortgage_isbased_in_rrr(
    mortgage_id varchar(40) NOT NULL,
    rrr_id varchar(40) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT mortgage_isbased_in_rrr_pkey PRIMARY KEY (mortgage_id,rrr_id)
);



-- Index mortgage_isbased_in_rrr_index_on_rowidentifier  --
CREATE INDEX mortgage_isbased_in_rrr_index_on_rowidentifier ON administrative.mortgage_isbased_in_rrr (rowidentifier);
    

comment on table administrative.mortgage_isbased_in_rrr is 'This is left in the data model but is not implemented, because the right that is basis for the mortgage can be implied by the primary right for ba_unit.

LADM Reference Object 
LA_Mortgage - LA_Right Relationship

LADM Definition
Identifies the right that is the basis for a mortgage.';
    
DROP TRIGGER IF EXISTS __track_changes ON administrative.mortgage_isbased_in_rrr CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON administrative.mortgage_isbased_in_rrr FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table administrative.mortgage_isbased_in_rrr_historic used for the history of data of table administrative.mortgage_isbased_in_rrr ---
DROP TABLE IF EXISTS administrative.mortgage_isbased_in_rrr_historic CASCADE;
CREATE TABLE administrative.mortgage_isbased_in_rrr_historic
(
    mortgage_id varchar(40),
    rrr_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index mortgage_isbased_in_rrr_historic_index_on_rowidentifier  --
CREATE INDEX mortgage_isbased_in_rrr_historic_index_on_rowidentifier ON administrative.mortgage_isbased_in_rrr_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON administrative.mortgage_isbased_in_rrr CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON administrative.mortgage_isbased_in_rrr FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table administrative.source_describes_rrr ----
DROP TABLE IF EXISTS administrative.source_describes_rrr CASCADE;
CREATE TABLE administrative.source_describes_rrr(
    rrr_id varchar(40) NOT NULL,
    source_id varchar(40) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT source_describes_rrr_pkey PRIMARY KEY (rrr_id,source_id)
);



-- Index source_describes_rrr_index_on_rowidentifier  --
CREATE INDEX source_describes_rrr_index_on_rowidentifier ON administrative.source_describes_rrr (rowidentifier);
    

comment on table administrative.source_describes_rrr is 'Implements the many-to-many relationship identifying administrative source instances with rrr instances
LADM Reference Object 
Relationship LA_AdministrativeSource - LA_RRR
LADM Definition
Not Defined';
    
DROP TRIGGER IF EXISTS __track_changes ON administrative.source_describes_rrr CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON administrative.source_describes_rrr FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table administrative.source_describes_rrr_historic used for the history of data of table administrative.source_describes_rrr ---
DROP TABLE IF EXISTS administrative.source_describes_rrr_historic CASCADE;
CREATE TABLE administrative.source_describes_rrr_historic
(
    rrr_id varchar(40),
    source_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index source_describes_rrr_historic_index_on_rowidentifier  --
CREATE INDEX source_describes_rrr_historic_index_on_rowidentifier ON administrative.source_describes_rrr_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON administrative.source_describes_rrr CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON administrative.source_describes_rrr FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table administrative.source_describes_ba_unit ----
DROP TABLE IF EXISTS administrative.source_describes_ba_unit CASCADE;
CREATE TABLE administrative.source_describes_ba_unit(
    ba_unit_id varchar(40) NOT NULL,
    source_id varchar(40) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT source_describes_ba_unit_pkey PRIMARY KEY (ba_unit_id,source_id)
);



-- Index source_describes_ba_unit_index_on_rowidentifier  --
CREATE INDEX source_describes_ba_unit_index_on_rowidentifier ON administrative.source_describes_ba_unit (rowidentifier);
    

comment on table administrative.source_describes_ba_unit is 'Implements the many-to-many relationship identifying administrative source instances with ba_unit instances
LADM Reference Object 
Relationship LA_AdministrativeSource - LA_BAUnit
LADM Definition
Not Defined';
    
DROP TRIGGER IF EXISTS __track_changes ON administrative.source_describes_ba_unit CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON administrative.source_describes_ba_unit FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table administrative.source_describes_ba_unit_historic used for the history of data of table administrative.source_describes_ba_unit ---
DROP TABLE IF EXISTS administrative.source_describes_ba_unit_historic CASCADE;
CREATE TABLE administrative.source_describes_ba_unit_historic
(
    ba_unit_id varchar(40),
    source_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index source_describes_ba_unit_historic_index_on_rowidentifier  --
CREATE INDEX source_describes_ba_unit_historic_index_on_rowidentifier ON administrative.source_describes_ba_unit_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON administrative.source_describes_ba_unit CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON administrative.source_describes_ba_unit FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table administrative.required_relationship_baunit ----
DROP TABLE IF EXISTS administrative.required_relationship_baunit CASCADE;
CREATE TABLE administrative.required_relationship_baunit(
    from_ba_unit_id varchar(40) NOT NULL,
    to_ba_unit_id varchar(40) NOT NULL,
    relation_code varchar(20) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT required_relationship_baunit_pkey PRIMARY KEY (from_ba_unit_id,to_ba_unit_id)
);



-- Index required_relationship_baunit_index_on_rowidentifier  --
CREATE INDEX required_relationship_baunit_index_on_rowidentifier ON administrative.required_relationship_baunit (rowidentifier);
    

comment on table administrative.required_relationship_baunit is 'Refer to LADM Definition
LADM Reference Object 
LA_RequiredRelationshipBAUnit
LADM Definition
A required relationship between basic administrative units.';
    
DROP TRIGGER IF EXISTS __track_changes ON administrative.required_relationship_baunit CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON administrative.required_relationship_baunit FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table administrative.required_relationship_baunit_historic used for the history of data of table administrative.required_relationship_baunit ---
DROP TABLE IF EXISTS administrative.required_relationship_baunit_historic CASCADE;
CREATE TABLE administrative.required_relationship_baunit_historic
(
    from_ba_unit_id varchar(40),
    to_ba_unit_id varchar(40),
    relation_code varchar(20),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index required_relationship_baunit_historic_index_on_rowidentifier  --
CREATE INDEX required_relationship_baunit_historic_index_on_rowidentifier ON administrative.required_relationship_baunit_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON administrative.required_relationship_baunit CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON administrative.required_relationship_baunit FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table cadastre.spatial_unit ----
DROP TABLE IF EXISTS cadastre.spatial_unit CASCADE;
CREATE TABLE cadastre.spatial_unit(
    id varchar(40) NOT NULL,
    dimension_code varchar(20) NOT NULL DEFAULT ('2D'),
    label varchar(255),
    surface_relation_code varchar(20) NOT NULL DEFAULT ('onSurface'),
    level_id varchar(40),
    reference_point GEOMETRY
        CONSTRAINT enforce_dims_reference_point CHECK (st_ndims(reference_point) = 2),
        CONSTRAINT enforce_srid_reference_point CHECK (st_srid(reference_point) = 32630),
        CONSTRAINT enforce_valid_reference_point CHECK (st_isvalid(reference_point)),
        CONSTRAINT enforce_geotype_reference_point CHECK (geometrytype(reference_point) = 'POINT'::text OR reference_point IS NULL),
    geom GEOMETRY
        CONSTRAINT enforce_dims_geom CHECK (st_ndims(geom) = 2),
        CONSTRAINT enforce_srid_geom CHECK (st_srid(geom) = 2193),
        CONSTRAINT enforce_valid_geom CHECK (st_isvalid(geom)),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT spatial_unit_pkey PRIMARY KEY (id)
);



-- Index spatial_unit_index_on_reference_point  --
CREATE INDEX spatial_unit_index_on_reference_point ON cadastre.spatial_unit using gist(reference_point);
    
-- Index spatial_unit_index_on_geom  --
CREATE INDEX spatial_unit_index_on_geom ON cadastre.spatial_unit using gist(geom);
    
-- Index spatial_unit_index_on_rowidentifier  --
CREATE INDEX spatial_unit_index_on_rowidentifier ON cadastre.spatial_unit (rowidentifier);
    

comment on table cadastre.spatial_unit is 'Single area (or multiple areas) of land or water, or a single volume (or multiple volumes) of space
LADM Reference Object 
LA_SpatialUnit
LADM Definition
Not Defined';
    
DROP TRIGGER IF EXISTS __track_changes ON cadastre.spatial_unit CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON cadastre.spatial_unit FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table cadastre.spatial_unit_historic used for the history of data of table cadastre.spatial_unit ---
DROP TABLE IF EXISTS cadastre.spatial_unit_historic CASCADE;
CREATE TABLE cadastre.spatial_unit_historic
(
    id varchar(40),
    dimension_code varchar(20),
    label varchar(255),
    surface_relation_code varchar(20),
    level_id varchar(40),
    reference_point GEOMETRY
        CONSTRAINT enforce_dims_reference_point CHECK (st_ndims(reference_point) = 2),
        CONSTRAINT enforce_srid_reference_point CHECK (st_srid(reference_point) = 32630),
        CONSTRAINT enforce_valid_reference_point CHECK (st_isvalid(reference_point)),
        CONSTRAINT enforce_geotype_reference_point CHECK (geometrytype(reference_point) = 'POINT'::text OR reference_point IS NULL),
    geom GEOMETRY
        CONSTRAINT enforce_dims_geom CHECK (st_ndims(geom) = 2),
        CONSTRAINT enforce_srid_geom CHECK (st_srid(geom) = 2193),
        CONSTRAINT enforce_valid_geom CHECK (st_isvalid(geom)),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index spatial_unit_historic_index_on_reference_point  --
CREATE INDEX spatial_unit_historic_index_on_reference_point ON cadastre.spatial_unit_historic using gist(reference_point);
    
-- Index spatial_unit_historic_index_on_geom  --
CREATE INDEX spatial_unit_historic_index_on_geom ON cadastre.spatial_unit_historic using gist(geom);
    
-- Index spatial_unit_historic_index_on_rowidentifier  --
CREATE INDEX spatial_unit_historic_index_on_rowidentifier ON cadastre.spatial_unit_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON cadastre.spatial_unit CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON cadastre.spatial_unit FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table cadastre.spatial_value_area ----
DROP TABLE IF EXISTS cadastre.spatial_value_area CASCADE;
CREATE TABLE cadastre.spatial_value_area(
    spatial_unit_id varchar(40) NOT NULL,
    type_code varchar(20) NOT NULL,
    size numeric(29, 2) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT spatial_value_area_pkey PRIMARY KEY (spatial_unit_id,type_code)
);



-- Index spatial_value_area_index_on_rowidentifier  --
CREATE INDEX spatial_value_area_index_on_rowidentifier ON cadastre.spatial_value_area (rowidentifier);
    

comment on table cadastre.spatial_value_area is 'Refer to LADM Definition
LADM Reference Object 
LA_AreaValue
LADM Definition
The area (size) of  2 dimension spatial unit';
    
DROP TRIGGER IF EXISTS __track_changes ON cadastre.spatial_value_area CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON cadastre.spatial_value_area FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table cadastre.spatial_value_area_historic used for the history of data of table cadastre.spatial_value_area ---
DROP TABLE IF EXISTS cadastre.spatial_value_area_historic CASCADE;
CREATE TABLE cadastre.spatial_value_area_historic
(
    spatial_unit_id varchar(40),
    type_code varchar(20),
    size numeric(29, 2),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index spatial_value_area_historic_index_on_rowidentifier  --
CREATE INDEX spatial_value_area_historic_index_on_rowidentifier ON cadastre.spatial_value_area_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON cadastre.spatial_value_area CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON cadastre.spatial_value_area FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table cadastre.area_type ----
DROP TABLE IF EXISTS cadastre.area_type CASCADE;
CREATE TABLE cadastre.area_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('c'),

    -- Internal constraints
    
    CONSTRAINT area_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT area_type_pkey PRIMARY KEY (code)
);


comment on table cadastre.area_type is 'Reference Table / Code list of the different versions or means of calculated area
LADM Reference Object 
LA_AreaType
LADM Definition
Not Defined';
    
 -- Data for the table cadastre.area_type -- 
insert into cadastre.area_type(code, display_value, status) values('calculatedArea', 'Calculated Area::::Area calcolata', 'c');
insert into cadastre.area_type(code, display_value, status) values('nonOfficialArea', 'Non-official Area::::Area Non ufficiale', 'c');
insert into cadastre.area_type(code, display_value, status) values('officialArea', 'Official Area::::Area Ufficiale', 'c');
insert into cadastre.area_type(code, display_value, status) values('surveyedArea', 'Surveyed Area::::Area Sorvegliata', 'c');



--Table cadastre.spatial_unit_address ----
DROP TABLE IF EXISTS cadastre.spatial_unit_address CASCADE;
CREATE TABLE cadastre.spatial_unit_address(
    spatial_unit_id varchar(40) NOT NULL,
    address_id varchar(40) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT spatial_unit_address_pkey PRIMARY KEY (spatial_unit_id,address_id)
);



-- Index spatial_unit_address_index_on_rowidentifier  --
CREATE INDEX spatial_unit_address_index_on_rowidentifier ON cadastre.spatial_unit_address (rowidentifier);
    

comment on table cadastre.spatial_unit_address is 'Implements the many-to-many relationship between address and spatial_unit
LADM Reference Object
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
DROP TRIGGER IF EXISTS __track_changes ON cadastre.spatial_unit_address CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON cadastre.spatial_unit_address FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table cadastre.spatial_unit_address_historic used for the history of data of table cadastre.spatial_unit_address ---
DROP TABLE IF EXISTS cadastre.spatial_unit_address_historic CASCADE;
CREATE TABLE cadastre.spatial_unit_address_historic
(
    spatial_unit_id varchar(40),
    address_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index spatial_unit_address_historic_index_on_rowidentifier  --
CREATE INDEX spatial_unit_address_historic_index_on_rowidentifier ON cadastre.spatial_unit_address_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON cadastre.spatial_unit_address CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON cadastre.spatial_unit_address FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table cadastre.surface_relation_type ----
DROP TABLE IF EXISTS cadastre.surface_relation_type CASCADE;
CREATE TABLE cadastre.surface_relation_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('t'),

    -- Internal constraints
    
    CONSTRAINT surface_relation_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT surface_relation_type_pkey PRIMARY KEY (code)
);


comment on table cadastre.surface_relation_type is 'Refer to LADM Definition
LADM Reference Object 
LA_SurfaceRelationType
LADM Definition
The  type of relation that exists between spatial objects and space (surface)';
    
 -- Data for the table cadastre.surface_relation_type -- 
insert into cadastre.surface_relation_type(code, display_value, status) values('above', 'Above::::Sopra', 'x');
insert into cadastre.surface_relation_type(code, display_value, status) values('below', 'Below::::Sotto', 'x');
insert into cadastre.surface_relation_type(code, display_value, status) values('mixed', 'Mixed::::Misto', 'x');
insert into cadastre.surface_relation_type(code, display_value, status) values('onSurface', 'On Surface::::Sulla Superficie', 'c');



--Table cadastre.level ----
DROP TABLE IF EXISTS cadastre.level CASCADE;
CREATE TABLE cadastre.level(
    id varchar(40) NOT NULL,
    name varchar(50),
    register_type_code varchar(20) NOT NULL,
    structure_code varchar(20),
    type_code varchar(20),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT level_pkey PRIMARY KEY (id)
);



-- Index level_index_on_rowidentifier  --
CREATE INDEX level_index_on_rowidentifier ON cadastre.level (rowidentifier);
    

comment on table cadastre.level is 'Refer to LADM Definition
LADM Reference Object 
LA_Level
LADM Definition
A set of spatial units, with a geometric, and/or topologic, and/or thematic coherence EXAMPLE 1 One level for an urban cadastre and another level for a rural cadastre. EXAMPLE 2 One level with rights and another level with restrictions. EXAMPLE 3 One level with formal rights, a second level with informal rights and a third level with customary rights. EXAMPLE 4 One level with point based spatial units, a second level with line based spatial units, and a third level with polygon based spatial units..';
    
DROP TRIGGER IF EXISTS __track_changes ON cadastre.level CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON cadastre.level FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table cadastre.level_historic used for the history of data of table cadastre.level ---
DROP TABLE IF EXISTS cadastre.level_historic CASCADE;
CREATE TABLE cadastre.level_historic
(
    id varchar(40),
    name varchar(50),
    register_type_code varchar(20),
    structure_code varchar(20),
    type_code varchar(20),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index level_historic_index_on_rowidentifier  --
CREATE INDEX level_historic_index_on_rowidentifier ON cadastre.level_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON cadastre.level CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON cadastre.level FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table cadastre.register_type ----
DROP TABLE IF EXISTS cadastre.register_type CASCADE;
CREATE TABLE cadastre.register_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT register_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT register_type_pkey PRIMARY KEY (code)
);


comment on table cadastre.register_type is 'Reference Table / Code list for register types
LADM Reference Object 
LA_
LADM Definition
The register type of the content of the [map] level';
    
 -- Data for the table cadastre.register_type -- 
insert into cadastre.register_type(code, display_value, status) values('all', 'All::::Tutti', 'c');
insert into cadastre.register_type(code, display_value, status) values('forest', 'Forest::::Forestale', 'c');
insert into cadastre.register_type(code, display_value, status) values('mining', 'Mining::::Minerario', 'c');
insert into cadastre.register_type(code, display_value, status) values('publicSpace', 'Public Space::::Spazio Pubblico', 'c');
insert into cadastre.register_type(code, display_value, status) values('rural', 'Rural::::Rurale', 'c');
insert into cadastre.register_type(code, display_value, status) values('urban', 'Urban::::Urbano', 'c');



--Table cadastre.structure_type ----
DROP TABLE IF EXISTS cadastre.structure_type CASCADE;
CREATE TABLE cadastre.structure_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('t'),

    -- Internal constraints
    
    CONSTRAINT structure_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT structure_type_pkey PRIMARY KEY (code)
);


comment on table cadastre.structure_type is 'Reference Table / Code list of different forms of spatial unit definitions (within a level)
LADM Reference Object 
LA_StructureType
LADM Definition
Not Defined';
    
 -- Data for the table cadastre.structure_type -- 
insert into cadastre.structure_type(code, display_value, status) values('point', 'Point::::Punto', 'c');
insert into cadastre.structure_type(code, display_value, status) values('polygon', 'Polygon::::Poligono', 'c');
insert into cadastre.structure_type(code, display_value, status) values('sketch', 'Sketch::::Schizzo', 'c');
insert into cadastre.structure_type(code, display_value, status) values('text', 'Text::::Testo', 'c');
insert into cadastre.structure_type(code, display_value, status) values('topological', 'Topological::::Topologico', 'c');
insert into cadastre.structure_type(code, display_value, status) values('unStructuredLine', 'UnstructuredLine::::LineanonDefinita', 'c');



--Table cadastre.level_content_type ----
DROP TABLE IF EXISTS cadastre.level_content_type CASCADE;
CREATE TABLE cadastre.level_content_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('t'),

    -- Internal constraints
    
    CONSTRAINT level_content_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT level_content_type_pkey PRIMARY KEY (code)
);


comment on table cadastre.level_content_type is 'Reference Table / Code list for the content type of a level
LADM Reference Object 
LA_
LADM Definition
The type of the content of the level;';
    
 -- Data for the table cadastre.level_content_type -- 
insert into cadastre.level_content_type(code, display_value, status) values('building', 'Building::::Costruzione', 'x');
insert into cadastre.level_content_type(code, display_value, status) values('customary', 'Customary::::Consueto', 'x');
insert into cadastre.level_content_type(code, display_value, status) values('informal', 'Informal::::Informale', 'x');
insert into cadastre.level_content_type(code, display_value, status) values('mixed', 'Mixed::::Misto', 'x');
insert into cadastre.level_content_type(code, display_value, status) values('network', 'Network::::Rete', 'x');
insert into cadastre.level_content_type(code, display_value, status) values('primaryRight', 'Primary Right::::Diritto Primario', 'c');
insert into cadastre.level_content_type(code, display_value, status) values('responsibility', 'Responsibility::::Responsabilita', 'x');
insert into cadastre.level_content_type(code, display_value, status) values('restriction', 'Restriction::::Restrizione', 'c');
insert into cadastre.level_content_type(code, display_value, description, status) values('geographicLocator', 'Geographic Locators::::Locatori Geografici', 'Extension to LADM', 'c');



--Table administrative.ba_unit_contains_spatial_unit ----
DROP TABLE IF EXISTS administrative.ba_unit_contains_spatial_unit CASCADE;
CREATE TABLE administrative.ba_unit_contains_spatial_unit(
    ba_unit_id varchar(40) NOT NULL,
    spatial_unit_id varchar(40) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT ba_unit_contains_spatial_unit_pkey PRIMARY KEY (ba_unit_id,spatial_unit_id)
);



-- Index ba_unit_contains_spatial_unit_index_on_rowidentifier  --
CREATE INDEX ba_unit_contains_spatial_unit_index_on_rowidentifier ON administrative.ba_unit_contains_spatial_unit (rowidentifier);
    

comment on table administrative.ba_unit_contains_spatial_unit is 'Defines the spatial unit(s) associated with ba_unit
LADM Reference Object 
Implements the many to many relationship LA_BAUnit - LA_SpatialUnit
LADM Definition 
Not defined
.';
    
DROP TRIGGER IF EXISTS __track_changes ON administrative.ba_unit_contains_spatial_unit CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON administrative.ba_unit_contains_spatial_unit FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table administrative.ba_unit_contains_spatial_unit_historic used for the history of data of table administrative.ba_unit_contains_spatial_unit ---
DROP TABLE IF EXISTS administrative.ba_unit_contains_spatial_unit_historic CASCADE;
CREATE TABLE administrative.ba_unit_contains_spatial_unit_historic
(
    ba_unit_id varchar(40),
    spatial_unit_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index ba_unit_contains_spatial_unit_historic_index_on_rowidentifier  --
CREATE INDEX ba_unit_contains_spatial_unit_historic_index_on_rowidentifier ON administrative.ba_unit_contains_spatial_unit_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON administrative.ba_unit_contains_spatial_unit CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON administrative.ba_unit_contains_spatial_unit FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table cadastre.legal_space_utility_network ----
DROP TABLE IF EXISTS cadastre.legal_space_utility_network CASCADE;
CREATE TABLE cadastre.legal_space_utility_network(
    id varchar(40) NOT NULL,
    ext_physical_network_id varchar(40),
    status_code varchar(20),
    type_code varchar(20) NOT NULL,
    geom GEOMETRY
        CONSTRAINT enforce_dims_geom CHECK (st_ndims(geom) = 2),
        CONSTRAINT enforce_srid_geom CHECK (st_srid(geom) = 2193),
        CONSTRAINT enforce_valid_geom CHECK (st_isvalid(geom)),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT legal_space_utility_network_pkey PRIMARY KEY (id)
);



-- Index legal_space_utility_network_index_on_geom  --
CREATE INDEX legal_space_utility_network_index_on_geom ON cadastre.legal_space_utility_network using gist(geom);
    
-- Index legal_space_utility_network_index_on_rowidentifier  --
CREATE INDEX legal_space_utility_network_index_on_rowidentifier ON cadastre.legal_space_utility_network (rowidentifier);
    

comment on table cadastre.legal_space_utility_network is 'Refer to LADM Definition
LADM Reference Object 
LA_LegalSpaceUtilityNetwork
LADM Definition
A utility network concerns legal space, which does not necessarily coincide with the physical space of a utility network..';
    
DROP TRIGGER IF EXISTS __track_changes ON cadastre.legal_space_utility_network CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON cadastre.legal_space_utility_network FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table cadastre.legal_space_utility_network_historic used for the history of data of table cadastre.legal_space_utility_network ---
DROP TABLE IF EXISTS cadastre.legal_space_utility_network_historic CASCADE;
CREATE TABLE cadastre.legal_space_utility_network_historic
(
    id varchar(40),
    ext_physical_network_id varchar(40),
    status_code varchar(20),
    type_code varchar(20),
    geom GEOMETRY
        CONSTRAINT enforce_dims_geom CHECK (st_ndims(geom) = 2),
        CONSTRAINT enforce_srid_geom CHECK (st_srid(geom) = 2193),
        CONSTRAINT enforce_valid_geom CHECK (st_isvalid(geom)),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index legal_space_utility_network_historic_index_on_geom  --
CREATE INDEX legal_space_utility_network_historic_index_on_geom ON cadastre.legal_space_utility_network_historic using gist(geom);
    
-- Index legal_space_utility_network_historic_index_on_rowidentifier  --
CREATE INDEX legal_space_utility_network_historic_index_on_rowidentifier ON cadastre.legal_space_utility_network_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON cadastre.legal_space_utility_network CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON cadastre.legal_space_utility_network FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table cadastre.building_unit_type ----
DROP TABLE IF EXISTS cadastre.building_unit_type CASCADE;
CREATE TABLE cadastre.building_unit_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('t'),

    -- Internal constraints
    
    CONSTRAINT building_unit_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT building_unit_type_pkey PRIMARY KEY (code)
);


comment on table cadastre.building_unit_type is 'Reference Table / Code list for types of building units
LADM Reference Object 
LA_BuildingUnitType
LADM Definition
Not Defined';
    
 -- Data for the table cadastre.building_unit_type -- 
insert into cadastre.building_unit_type(code, display_value, status) values('individual', 'Individual::::Individuale', 'c');
insert into cadastre.building_unit_type(code, display_value, status) values('shared', 'Shared::::Condiviso', 'c');



--Table cadastre.utility_network_status_type ----
DROP TABLE IF EXISTS cadastre.utility_network_status_type CASCADE;
CREATE TABLE cadastre.utility_network_status_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('t'),

    -- Internal constraints
    
    CONSTRAINT utility_network_status_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT utility_network_status_type_pkey PRIMARY KEY (code)
);


comment on table cadastre.utility_network_status_type is 'Reference Table / Code list for the status of utility networks
LADM Reference Object 
LA_UtilityNetworkStatusType
LADM Definition
Status of the type of utility network';
    
 -- Data for the table cadastre.utility_network_status_type -- 
insert into cadastre.utility_network_status_type(code, display_value, status) values('inUse', 'In Use::::In uso', 'c');
insert into cadastre.utility_network_status_type(code, display_value, status) values('outOfUse', 'Out of Use::::Fuori uso', 'c');
insert into cadastre.utility_network_status_type(code, display_value, status) values('planned', 'Planned::::Pianificato', 'c');



--Table cadastre.utility_network_type ----
DROP TABLE IF EXISTS cadastre.utility_network_type CASCADE;
CREATE TABLE cadastre.utility_network_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT utility_network_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT utility_network_type_pkey PRIMARY KEY (code)
);


comment on table cadastre.utility_network_type is 'Reference Table / Code list of utility network types
LADM Reference Object 
LA_
LADM Definition
Not Defined';
    
 -- Data for the table cadastre.utility_network_type -- 
insert into cadastre.utility_network_type(code, display_value, status) values('chemical', 'Chemicals::::Cimica', 'c');
insert into cadastre.utility_network_type(code, display_value, status) values('electricity', 'Electricity::::Elettricita', 'c');
insert into cadastre.utility_network_type(code, display_value, status) values('gas', 'Gas::::Gas', 'c');
insert into cadastre.utility_network_type(code, display_value, status) values('heating', 'Heating::::Riscaldamento', 'c');
insert into cadastre.utility_network_type(code, display_value, status) values('oil', 'Oil::::Carburante', 'c');
insert into cadastre.utility_network_type(code, display_value, status) values('telecommunication', 'Telecommunication::::Telecomunicazione', 'c');
insert into cadastre.utility_network_type(code, display_value, status) values('water', 'Water::::Acqua', 'c');



--Table application.application ----
DROP TABLE IF EXISTS application.application CASCADE;
CREATE TABLE application.application(
    id varchar(40) NOT NULL,
    nr varchar(15) NOT NULL,
    lodging_datetime timestamp NOT NULL DEFAULT (now()),
    expected_completion_date date DEFAULT (now()),
    assignee_id varchar(40),
    assigned_datetime timestamp,
    location GEOMETRY
        CONSTRAINT enforce_dims_location CHECK (st_ndims(location) = 2),
        CONSTRAINT enforce_srid_location CHECK (st_srid(location) = 32630),
        CONSTRAINT enforce_valid_location CHECK (st_isvalid(location)),
        CONSTRAINT enforce_geotype_location CHECK (geometrytype(location) = 'MULTIPOINT'::text OR location IS NULL),
    total_fee numeric(20, 2) NOT NULL DEFAULT (0),
    total_amount_paid numeric(20, 2) NOT NULL DEFAULT (0),
    request_code varchar(50) NOT NULL,
    regional_number varchar(15),
    target_locality varchar(200),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT application_check_assigned CHECK ((assignee_id is null and assigned_datetime is null) or (assignee_id is not null and assigned_datetime is not null)),
    CONSTRAINT application_pkey PRIMARY KEY (id)
);



-- Index application_index_on_location  --
CREATE INDEX application_index_on_location ON application.application using gist(location);
    
-- Index application_index_on_rowidentifier  --
CREATE INDEX application_index_on_rowidentifier ON application.application (rowidentifier);
    

comment on table application.application is 'An application is a bundle of services that a client or customer wants from the registration office.
LADM Reference Object
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
DROP TRIGGER IF EXISTS __track_changes ON application.application CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON application.application FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table application.application_historic used for the history of data of table application.application ---
DROP TABLE IF EXISTS application.application_historic CASCADE;
CREATE TABLE application.application_historic
(
    id varchar(40),
    nr varchar(15),
    lodging_datetime timestamp,
    expected_completion_date date,
    assignee_id varchar(40),
    assigned_datetime timestamp,
    location GEOMETRY
        CONSTRAINT enforce_dims_location CHECK (st_ndims(location) = 2),
        CONSTRAINT enforce_srid_location CHECK (st_srid(location) = 32630),
        CONSTRAINT enforce_valid_location CHECK (st_isvalid(location)),
        CONSTRAINT enforce_geotype_location CHECK (geometrytype(location) = 'MULTIPOINT'::text OR location IS NULL),
    total_fee numeric(20, 2),
    total_amount_paid numeric(20, 2),
    request_code varchar(50),
    regional_number varchar(15),
    target_locality varchar(200),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index application_historic_index_on_location  --
CREATE INDEX application_historic_index_on_location ON application.application_historic using gist(location);
    
-- Index application_historic_index_on_rowidentifier  --
CREATE INDEX application_historic_index_on_rowidentifier ON application.application_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON application.application CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON application.application FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
 -- Extra script for the table application.application -- 
CREATE INDEX application_historic_id_ind ON application.application_historic (id);


--Table application.request_type ----
DROP TABLE IF EXISTS application.request_type CASCADE;
CREATE TABLE application.request_type(
    code varchar(50) NOT NULL,
    request_category_code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('t'),
    nr_days_to_complete integer NOT NULL DEFAULT (0),
    base_fee numeric(20, 2) NOT NULL DEFAULT (0),
    area_base_fee numeric(20, 2) NOT NULL DEFAULT (0),
    value_base_fee numeric(20, 2) NOT NULL DEFAULT (0),
    nr_properties_required integer NOT NULL DEFAULT (0),
    notation_template varchar(1000),
    rrr_type_code varchar(20),
    type_action_code varchar(20),
    starting_status_code varchar(50) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT request_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT request_type_pkey PRIMARY KEY (code)
);


comment on table application.request_type is 'Reference Table / Code list of the (service) request types received by a land office
LADM Reference Object 
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
 -- Data for the table application.request_type -- 
insert into application.request_type(code, request_category_code, display_value, status, nr_days_to_complete, base_fee, area_base_fee, value_base_fee, nr_properties_required, starting_status_code) values('smd-plancertification', 'registrationServices', 'Plan certification', 'c', 10, 100, 100, 100, 100, 'smd-plancertification-received');
insert into application.request_type(code, request_category_code, display_value, status, nr_days_to_complete, base_fee, area_base_fee, value_base_fee, nr_properties_required, starting_status_code) values('smd-regnr', 'registrationServices', 'Regional number', 'c', 10, 100, 100, 100, 100, 'smd-regnr-received');
insert into application.request_type(code, request_category_code, display_value, status, nr_days_to_complete, base_fee, area_base_fee, value_base_fee, nr_properties_required, starting_status_code) values('cadastreChange', 'registrationServices', 'New parcel', 'c', 10, 100, 100, 100, 1, 'smd-cadchange-submit');
insert into application.request_type(code, request_category_code, display_value, status, nr_days_to_complete, base_fee, area_base_fee, value_base_fee, nr_properties_required, starting_status_code) values('redefineCadastre', 'registrationServices', 'Edit parcel', 'c', 10, 100, 100, 100, 1, 'smd-cadredef-submit');



--Table application.request_category_type ----
DROP TABLE IF EXISTS application.request_category_type CASCADE;
CREATE TABLE application.request_category_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('t'),

    -- Internal constraints
    
    CONSTRAINT request_category_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT request_category_type_pkey PRIMARY KEY (code)
);


comment on table application.request_category_type is 'Reference Table / Code list for categories of (service) requests received by a land office
LADM Reference Object 
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
 -- Data for the table application.request_category_type -- 
insert into application.request_category_type(code, display_value, status) values('registrationServices', 'Registration Services::::Servizi di Registrazione', 'c');
insert into application.request_category_type(code, display_value, status) values('informationServices', 'Information Services::::Servizi Informativi', 'c');



--Table party.party_role ----
DROP TABLE IF EXISTS party.party_role CASCADE;
CREATE TABLE party.party_role(
    party_id varchar(40) NOT NULL,
    type_code varchar(20) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT party_role_pkey PRIMARY KEY (party_id,type_code)
);



-- Index party_role_index_on_rowidentifier  --
CREATE INDEX party_role_index_on_rowidentifier ON party.party_role (rowidentifier);
    

comment on table party.party_role is 'Records the role(s) a party has in land office processes
LADM Reference Object
FLOSS SOLA Extension LA_Party.role
LADM Definition
The role of a party in the data update and maintenance process';
    
DROP TRIGGER IF EXISTS __track_changes ON party.party_role CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON party.party_role FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table party.party_role_historic used for the history of data of table party.party_role ---
DROP TABLE IF EXISTS party.party_role_historic CASCADE;
CREATE TABLE party.party_role_historic
(
    party_id varchar(40),
    type_code varchar(20),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index party_role_historic_index_on_rowidentifier  --
CREATE INDEX party_role_historic_index_on_rowidentifier ON party.party_role_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON party.party_role CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON party.party_role FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table party.party_role_type ----
DROP TABLE IF EXISTS party.party_role_type CASCADE;
CREATE TABLE party.party_role_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    used_in_application bool NOT NULL DEFAULT (false),
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT party_role_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT party_role_type_pkey PRIMARY KEY (code)
);


comment on table party.party_role_type is 'Reference Table / Code list of types of party roles
LADM Reference Object 
LA_
LADM Definition
The role of the party in the data update and maintenance process;';
    
 -- Data for the table party.party_role_type -- 
insert into party.party_role_type(code, display_value, status) values('conveyor', 'Conveyor::::Trasportatore', 'x');
insert into party.party_role_type(code, display_value, status) values('notary', 'Notary::::Notaio', 'c');
insert into party.party_role_type(code, display_value, status) values('writer', 'Writer::::Autore', 'x');
insert into party.party_role_type(code, display_value, status) values('surveyor', 'Surveyor::::Perito', 'x');
insert into party.party_role_type(code, display_value, used_in_application, status) values('certifiedSurveyor', 'Licenced Surveyor', true, 'c');
insert into party.party_role_type(code, display_value, status) values('bank', 'Bank::::Banca', 'c');
insert into party.party_role_type(code, display_value, status) values('moneyProvider', 'Money Provider::::Istituto Credito', 'c');
insert into party.party_role_type(code, display_value, status) values('employee', 'Employee::::Impiegato', 'x');
insert into party.party_role_type(code, display_value, status) values('farmer', 'Farmer::::Contadino', 'x');
insert into party.party_role_type(code, display_value, status) values('citizen', 'Citizen::::Cittadino', 'c');
insert into party.party_role_type(code, display_value, status) values('stateAdministrator', 'Registrar / Approving Surveyor::::Cancelleriere/ Perito Approvatore/', 'c');
insert into party.party_role_type(code, display_value, status, description) values('landOfficer', 'Land Officer::::Ufficiale del Registro Territoriale', 'c', 'Extension to LADM');
insert into party.party_role_type(code, display_value, used_in_application, status, description) values('lodgingAgent', 'Lodging Agent', true, 'c', 'Extension to LADM');
insert into party.party_role_type(code, display_value, status, description) values('powerOfAttorney', 'Power of Attorney::::Procuratore', 'c', 'Extension to LADM');
insert into party.party_role_type(code, display_value, status, description) values('transferee', 'Transferee (to)::::Avente Causa', 'c', 'Extension to LADM');
insert into party.party_role_type(code, display_value, status, description) values('transferor', 'Transferor (from)::::Dante Causa', 'c', 'Extension to LADM');
insert into party.party_role_type(code, display_value, used_in_application, status, description) values('applicant', 'Applicant', true, 'c', 'Extension to LADM');
insert into party.party_role_type(code, display_value, used_in_application, status, description) values('client', 'Client', true, 'c', 'Extension to LADM');



--Table address.address ----
DROP TABLE IF EXISTS address.address CASCADE;
CREATE TABLE address.address(
    id varchar(40) NOT NULL,
    description varchar(255),
    ext_address_id varchar(40),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT address_pkey PRIMARY KEY (id)
);



-- Index address_index_on_rowidentifier  --
CREATE INDEX address_index_on_rowidentifier ON address.address (rowidentifier);
    

comment on table address.address is 'Describes a postal or location address
LADM Reference Object
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
DROP TRIGGER IF EXISTS __track_changes ON address.address CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON address.address FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table address.address_historic used for the history of data of table address.address ---
DROP TABLE IF EXISTS address.address_historic CASCADE;
CREATE TABLE address.address_historic
(
    id varchar(40),
    description varchar(255),
    ext_address_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index address_historic_index_on_rowidentifier  --
CREATE INDEX address_historic_index_on_rowidentifier ON address.address_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON address.address CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON address.address FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table system.appuser ----
DROP TABLE IF EXISTS system.appuser CASCADE;
CREATE TABLE system.appuser(
    id varchar(40) NOT NULL,
    username varchar(40) NOT NULL,
    first_name varchar(30) NOT NULL,
    last_name varchar(30) NOT NULL,
    passwd varchar(100) NOT NULL DEFAULT (uuid_generate_v1()),
    active bool NOT NULL DEFAULT (true),
    description varchar(255),
    office_code varchar(40),
    office_head bool NOT NULL DEFAULT (false),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT appuser_username_unique UNIQUE (username),
    CONSTRAINT appuser_pkey PRIMARY KEY (id)
);



-- Index appuser_index_on_rowidentifier  --
CREATE INDEX appuser_index_on_rowidentifier ON system.appuser (rowidentifier);
    

comment on table system.appuser is 'This table contains list of users, who has an access to the application, can login and do certain actions.';
    
DROP TRIGGER IF EXISTS __track_changes ON system.appuser CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON system.appuser FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table system.appuser_historic used for the history of data of table system.appuser ---
DROP TABLE IF EXISTS system.appuser_historic CASCADE;
CREATE TABLE system.appuser_historic
(
    id varchar(40),
    username varchar(40),
    first_name varchar(30),
    last_name varchar(30),
    passwd varchar(100),
    active bool,
    description varchar(255),
    office_code varchar(40),
    office_head bool,
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index appuser_historic_index_on_rowidentifier  --
CREATE INDEX appuser_historic_index_on_rowidentifier ON system.appuser_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON system.appuser CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON system.appuser FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
 -- Data for the table system.appuser -- 
insert into system.appuser(id, username, first_name, last_name, passwd, active, office_code, office_head) values('csau-head', 'csau-head', 'CSAU', 'Head', '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08', true, 'csau', true);
insert into system.appuser(id, username, first_name, last_name, passwd, active, office_code, office_head) values('smd-registry-head', 'registry-head', 'Registry', 'Head', '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08', true, 'smd-registry', true);
insert into system.appuser(id, username, first_name, last_name, passwd, active, office_code, office_head) values('gis-section-head', 'gis-head', 'Gis', 'Head', '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08', true, 'cartographic-gis-section', true);
insert into system.appuser(id, username, first_name, last_name, passwd, active, office_code, office_head) values('gis-section-normal', 'gismdw', 'GIS', 'Normal', '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08', true, 'cartographic-gis-section', false);
insert into system.appuser(id, username, first_name, last_name, passwd, active, office_code, office_head) values('csau-normal', 'csau-normal', 'CSAU', 'Normal', '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08', true, 'csau', false);
insert into system.appuser(id, username, first_name, last_name, passwd, active, office_code, office_head) values('smd-registry-normal', 'registry-normal', 'Registry', 'Normal', '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08', true, 'smd-registry', false);
insert into system.appuser(id, username, first_name, last_name, passwd, active, office_code, office_head) values('archive-head', 'archive-head', 'Archive', 'Head', '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08', true, 'archive', true);
insert into system.appuser(id, username, first_name, last_name, passwd, active, office_code, office_head) values('admin', 'admin', 'Admin', 'Admin', '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08', true, 'it', false);



--Table cadastre.dimension_type ----
DROP TABLE IF EXISTS cadastre.dimension_type CASCADE;
CREATE TABLE cadastre.dimension_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('t'),

    -- Internal constraints
    
    CONSTRAINT dimension_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT dimension_type_pkey PRIMARY KEY (code)
);


comment on table cadastre.dimension_type is 'Reference Table / Code list to identify the number of dimensions used to define a spatial unit
LADM Reference Object 
LA_DimensionType
LADM Definition
Not Defined';
    
 -- Data for the table cadastre.dimension_type -- 
insert into cadastre.dimension_type(code, display_value, status) values('0D', '0D::::0D', 'c');
insert into cadastre.dimension_type(code, display_value, status) values('1D', '1D::::1D', 'c');
insert into cadastre.dimension_type(code, display_value, status) values('2D', '2D::::sD', 'c');
insert into cadastre.dimension_type(code, display_value, status) values('3D', '3D::::3D', 'c');
insert into cadastre.dimension_type(code, display_value, status) values('liminal', 'Liminal', 'x');



--Table party.communication_type ----
DROP TABLE IF EXISTS party.communication_type CASCADE;
CREATE TABLE party.communication_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT communication_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT communication_type_pkey PRIMARY KEY (code)
);


comment on table party.communication_type is 'Reference Table / Code list for the different means of communication (from land office to their clients)
LADM Reference Object 
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
 -- Data for the table party.communication_type -- 
insert into party.communication_type(code, display_value, status) values('eMail', 'e-Mail', 'c');
insert into party.communication_type(code, display_value, status) values('fax', 'Fax', 'c');
insert into party.communication_type(code, display_value, status) values('post', 'Post', 'c');
insert into party.communication_type(code, display_value, status) values('phone', 'Phone', 'c');
insert into party.communication_type(code, display_value, status) values('courier', 'Courier', 'c');



--Table source.presentation_form_type ----
DROP TABLE IF EXISTS source.presentation_form_type CASCADE;
CREATE TABLE source.presentation_form_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT presentation_form_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT presentation_form_type_pkey PRIMARY KEY (code)
);


comment on table source.presentation_form_type is 'Reference Table / Code list for the different formats of sources (documents) that are presented to the land office
LADM Reference Object 
CI_PresentationFormCode
LADM Definition
The type of document;';
    
 -- Data for the table source.presentation_form_type -- 
insert into source.presentation_form_type(code, display_value, status) values('documentDigital', 'Digital Document::::Documento Digitale', 'c');
insert into source.presentation_form_type(code, display_value, status) values('documentHardcopy', 'Hardcopy Document::::Documento in Hardcopy', 'c');
insert into source.presentation_form_type(code, display_value, status) values('imageDigital', 'Digital Image::::Immagine Digitale', 'c');
insert into source.presentation_form_type(code, display_value, status) values('imageHardcopy', 'Hardcopy Image::::Immagine in Hardcopy', 'c');
insert into source.presentation_form_type(code, display_value, status) values('mapDigital', 'Digital Map::::Mappa Digitale', 'c');
insert into source.presentation_form_type(code, display_value, status) values('mapHardcopy', 'Hardcopy Map::::Mappa in Hardcopy', 'c');
insert into source.presentation_form_type(code, display_value, status) values('modelDigital', 'Digital Model::::Modello Digitale'',', 'c');
insert into source.presentation_form_type(code, display_value, status) values('modelHarcopy', 'Hardcopy Model::::Modello in Hardcopy', 'c');
insert into source.presentation_form_type(code, display_value, status) values('profileDigital', 'Digital Profile::::Profilo Digitale', 'c');
insert into source.presentation_form_type(code, display_value, status) values('profileHardcopy', 'Hardcopy Profile::::Profilo in Hardcopy', 'c');
insert into source.presentation_form_type(code, display_value, status) values('tableDigital', 'Digital Table::::Tabella Digitale', 'c');
insert into source.presentation_form_type(code, display_value, status) values('tableHardcopy', 'Hardcopy Table::::Tabella in Hardcopy', 'c');
insert into source.presentation_form_type(code, display_value, status) values('videoDigital', 'Digital Video::::Video Digitale'',', 'c');
insert into source.presentation_form_type(code, display_value, status) values('videoHardcopy', 'Hardcopy Video::::Video in Hardcopy', 'c');



--Table source.archive ----
DROP TABLE IF EXISTS source.archive CASCADE;
CREATE TABLE source.archive(
    id varchar(40) NOT NULL,
    box_nr varchar(50) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT archive_pkey PRIMARY KEY (id)
);



-- Index archive_index_on_rowidentifier  --
CREATE INDEX archive_index_on_rowidentifier ON source.archive (rowidentifier);
    

comment on table source.archive is 'Details about collections of sources (documents) in both paper and digital formats
LADM Reference Object
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
DROP TRIGGER IF EXISTS __track_changes ON source.archive CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON source.archive FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table source.archive_historic used for the history of data of table source.archive ---
DROP TABLE IF EXISTS source.archive_historic CASCADE;
CREATE TABLE source.archive_historic
(
    id varchar(40),
    box_nr varchar(50),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index archive_historic_index_on_rowidentifier  --
CREATE INDEX archive_historic_index_on_rowidentifier ON source.archive_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON source.archive CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON source.archive FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table application.application_action_type ----
DROP TABLE IF EXISTS application.application_action_type CASCADE;
CREATE TABLE application.application_action_type(
    code varchar(50) NOT NULL,
    start_status_type_code varchar(50),
    display_value varchar(250) NOT NULL,
    next_status_type_code varchar(50),
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),
    action_order integer NOT NULL,
    gui_type varchar(50),
    operation varchar(20) NOT NULL DEFAULT ('normal'),

    -- Internal constraints
    
    CONSTRAINT application_action_type_pkey PRIMARY KEY (code)
);


comment on table application.application_action_type is 'The list of potential action types. Usually an action belongs to a certain status. 
There are actions that does not belong to a certain status, but can be taken in any moment in the application.';
    
 -- Data for the table application.application_action_type -- 
insert into application.application_action_type(code, start_status_type_code, display_value, status, description, action_order) values('smd-regnr-received-vetchecklist', 'smd-regnr-received', 'Vet against checklist', 'c', 'Check if required infromation is collected.', 10);
insert into application.application_action_type(code, start_status_type_code, display_value, status, description, action_order) values('smd-regnr-receivepayment', 'smd-regnr-vetted', 'Receive payment', 'c', 'Check if the payment is fully made.', 10);
insert into application.application_action_type(code, start_status_type_code, display_value, status, description, action_order) values('smd-plancertification-vetchecklist', 'smd-plancertification-received', 'Vet against checklist', 'c', 'Check if required infromation is collected.', 10);
insert into application.application_action_type(code, start_status_type_code, display_value, status, description, action_order) values('smd-plancertification-receivepay', 'smd-plancertification-received', 'Receive payment', 'c', 'Check if the payment is fully made.', 20);
insert into application.application_action_type(code, start_status_type_code, display_value, status, description, action_order, gui_type) values('smd-plancertification-generate', 'smd-plancertification-received', 'Generate plan', 'c', 'The plan generation starts from this screen.', 30, 'MapRequestActionPanel');
insert into application.application_action_type(code, start_status_type_code, display_value, status, description, action_order, gui_type) values('smdcadchange-make-changes', 'smd-cadchange-make-changes', 'Change map (split/merge/new)', 'c', 'The cadastre change process starts by clicking in the Make changes button.', 10, 'MapRequestActionPanel');
insert into application.application_action_type(code, start_status_type_code, display_value, status, description, action_order) values('smdcadchange-vetchecklist', 'smd-cadchange-submit', 'Vet against checklist', 'c', 'Check if required infromation is collected.', 10);
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order) values('smdcadchange-move-to-change', 'smd-cadchange-submit', 'Go to Make Changes', 'smd-cadchange-make-changes', 'c', 'Move to the status where the cadastre change can start.', 20);
insert into application.application_action_type(code, start_status_type_code, display_value, status, description, action_order, gui_type) values('smd-regnr-paid-assign-nr', 'smd-regnr-paid', 'Assign Regional No. and print', 'c', 'Generate regional number by clicking the button below.', 10, 'RegionalNumberGenerationActionPanel');
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order, operation) values('smdcadchange-set-completed', 'smd-cadchange-make-changes', 'Complete', 'smd-cadchange-completed', 'c', 'The application moves to completed status.', 40, 'approve');
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order, operation) values('smdcadchange-set-cancelled', 'smd-cadchange-make-changes', 'Cancel', 'smd-cadchange-cancelled', 'c', 'The application will be cancelled.', 50, 'cancel');
insert into application.application_action_type(code, start_status_type_code, display_value, status, description, action_order) values('smdcadchange-receivepayment', 'smd-cadchange-submit', 'Receive payment', 'c', 'Check if the payment is fully made.', 15);
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order, operation) values('smd-plancertification-set-completed', 'smd-plancertification-received', 'Complete', 'smd-plancertification-completed', 'c', 'The application moves to completed status.', 50, 'approve');
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order, gui_type, operation) values('smd-plancertification-set-cancelled', 'smd-plancertification-received', 'Cancel', 'smd-plancertification-cancelled', 'c', 'The application will be cancelled.', 60, 'MultipleRequestsActionPanel', 'cancel');
insert into application.application_action_type(code, start_status_type_code, display_value, status, description, action_order) values('smdcadredef-submit-vetchecklist', 'smd-cadredef-submit', 'Vet against checklist', 'c', 'Check if required infromation is collected.', 10);
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order) values('smdcadredef-submit-makechanges', 'smd-cadredef-submit', 'Go to make changes', 'smd-cadredef-make-changes', 'c', 'It moves the application in the status to make changes.', 20);
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order, operation) values('smdcadredef-submit-cancel', 'smd-cadredef-submit', 'Cancel', 'smd-cadredef-cancelled', 'c', 'It cancells the application.', 30, 'cancel');
insert into application.application_action_type(code, start_status_type_code, display_value, status, description, action_order, gui_type) values('smdcadredef-makechanges-makechanges', 'smd-cadredef-make-changes', 'Make changes', 'c', 'From this screen, the operation of changing/removing/adding nodes of cadastre objects can happen.', 10, 'MapRequestActionPanel');
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order, operation) values('smdcadredef-makechanges-complete', 'smd-cadredef-make-changes', 'Complete', 'smd-cadredef-completed', 'c', 'It approves the changes.', 20, 'approve');
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order, operation) values('smdcadredef-makechanges-approve', 'smd-cadredef-make-changes', 'Cancel', 'smd-cadredef-cancelled', 'c', 'It cancells the changes and the application.', 30, 'cancel');
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order) values('smd-regnr-received-set-vetted', 'smd-regnr-received', 'Change status to vetted', 'smd-regnr-vetted', 'c', 'It changes the status of the application to Vetted.', 20);
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order, operation) values('smd-regnr-received-set-rejected', 'smd-regnr-received', 'Reject', 'smd-regnr-rejected', 'c', 'It rejects the application.', 30, 'cancel');
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order) values('smd-regnr-vetted-set-paid', 'smd-regnr-vetted', 'Change status to paid', 'smd-regnr-paid', 'c', 'It changes the status to Paid.', 20);
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order) values('smd-regnr-vetted-set-rejected', 'smd-regnr-vetted', 'Reject', 'smd-regnr-rejected', 'c', 'It rejects the application.', 30);
insert into application.application_action_type(code, start_status_type_code, display_value, next_status_type_code, status, description, action_order, operation) values('smd-regnr-paid-set-completed', 'smd-regnr-paid', 'Complete', 'smd-regnr-completed', 'c', 'It changes the status of the application to Completed.', 20, 'approve');



--Table party.id_type ----
DROP TABLE IF EXISTS party.id_type CASCADE;
CREATE TABLE party.id_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT id_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT id_type_pkey PRIMARY KEY (code)
);


comment on table party.id_type is 'Reference Table / Code list for the types of the documents that can be used to identify a party.
LADM Reference Object 
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
 -- Data for the table party.id_type -- 
insert into party.id_type(code, display_value, status, description) values('nationalID', 'National ID', 'c', 'The main person ID that exists in the country::::Il principale documento identificativo nel paese');
insert into party.id_type(code, display_value, status, description) values('nationalPassport', 'National Passport', 'c', 'A passport issued by the country::::Passaporto fornito dal paese');
insert into party.id_type(code, display_value, status, description) values('otherPassport', 'Other Passport', 'c', 'A passport issued by another country::::Passaporto Fornito da un altro paese');
insert into party.id_type(code, display_value, status, description) values('surveyorId', 'Surveyor ID', 'c', 'An id that is given to a surveyor');



--Table application.service_action_type ----
DROP TABLE IF EXISTS application.service_action_type CASCADE;
CREATE TABLE application.service_action_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status_to_set varchar(20),
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT service_action_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT service_action_type_pkey PRIMARY KEY (code)
);


comment on table application.service_action_type is 'Reference Table / Code list of types of action that a land officer can perform to complete a service request
LADM Reference Object 
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
 -- Data for the table application.service_action_type -- 
insert into application.service_action_type(code, display_value, status, description) values('lodge', 'Lodge::::Registrata', 'c', 'Application for service(s) is officially received by land office (action is automatically logged when application is saved for the first time)::::La pratica per i servizi formalmente ricevuta da ufficio territoriale');
insert into application.service_action_type(code, display_value, status, description) values('start', 'Start::::Comincia', 'c', 'Provisional RRR Changes Made to Database as a result of application (action is automatically logged when a change is made to a rrr object)::::Apportate Modifiche Provvisorie di tipo RRR al Database come risultato della pratica');
insert into application.service_action_type(code, display_value, status, description) values('cancel', 'Cancel::::Cancella la pratica', 'c', 'Service is cancelled by Land Office (action is automatically logged when a service is cancelled)::::Pratica cancellata da Ufficio Territoriale');
insert into application.service_action_type(code, display_value, status, description) values('complete', 'Complete::::Completa', 'c', 'Application is ready for approval (action is automatically logged when service is marked as complete::::Pratica pronta per approvazione');
insert into application.service_action_type(code, display_value, status, description) values('revert', 'Revert::::ITALIANO', 'c', 'The status of the service has been reverted to pending from being completed (action is automatically logged when a service is reverted back for further work)::::ITALIANO');



--Table application.application_property ----
DROP TABLE IF EXISTS application.application_property CASCADE;
CREATE TABLE application.application_property(
    application_id varchar(40) NOT NULL,
    ba_unit_id varchar(40) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT application_property_pkey PRIMARY KEY (application_id,ba_unit_id)
);



-- Index application_property_index_on_rowidentifier  --
CREATE INDEX application_property_index_on_rowidentifier ON application.application_property (rowidentifier);
    

comment on table application.application_property is 'Details of the property associated with an application';
    
DROP TRIGGER IF EXISTS __track_changes ON application.application_property CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON application.application_property FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table application.application_property_historic used for the history of data of table application.application_property ---
DROP TABLE IF EXISTS application.application_property_historic CASCADE;
CREATE TABLE application.application_property_historic
(
    application_id varchar(40),
    ba_unit_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index application_property_historic_index_on_rowidentifier  --
CREATE INDEX application_property_historic_index_on_rowidentifier ON application.application_property_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON application.application_property CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON application.application_property FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table application.application_uses_source ----
DROP TABLE IF EXISTS application.application_uses_source CASCADE;
CREATE TABLE application.application_uses_source(
    id varchar(40) NOT NULL,
    application_id varchar(40) NOT NULL,
    source_id varchar(40) NOT NULL,
    is_primary bool NOT NULL DEFAULT (false),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT application_uses_source_pkey PRIMARY KEY (id)
);



-- Index application_uses_source_index_on_rowidentifier  --
CREATE INDEX application_uses_source_index_on_rowidentifier ON application.application_uses_source (rowidentifier);
    

comment on table application.application_uses_source is 'Sources (documents) submitted with an application, created as a result of the application by land officers or further documents added to assist in the processing of the application
LADM Reference Object
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
DROP TRIGGER IF EXISTS __track_changes ON application.application_uses_source CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON application.application_uses_source FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table application.application_uses_source_historic used for the history of data of table application.application_uses_source ---
DROP TABLE IF EXISTS application.application_uses_source_historic CASCADE;
CREATE TABLE application.application_uses_source_historic
(
    id varchar(40),
    application_id varchar(40),
    source_id varchar(40),
    is_primary bool,
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index application_uses_source_historic_index_on_rowidentifier  --
CREATE INDEX application_uses_source_historic_index_on_rowidentifier ON application.application_uses_source_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON application.application_uses_source CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON application.application_uses_source FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table application.request_type_requires_source_type ----
DROP TABLE IF EXISTS application.request_type_requires_source_type CASCADE;
CREATE TABLE application.request_type_requires_source_type(
    source_type_code varchar(20) NOT NULL,
    request_type_code varchar(50) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT request_type_requires_source_type_pkey PRIMARY KEY (source_type_code,request_type_code)
);


comment on table application.request_type_requires_source_type is 'Source (documents) required for a particular (Service) Request received by a land office
LADM Reference Object
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
 -- Data for the table application.request_type_requires_source_type -- 
insert into application.request_type_requires_source_type(source_type_code, request_type_code) values('sitePlan', 'smd-plancertification');
insert into application.request_type_requires_source_type(source_type_code, request_type_code) values('idVerification', 'smd-plancertification');
insert into application.request_type_requires_source_type(source_type_code, request_type_code) values('sitePlan', 'cadastreChange');
insert into application.request_type_requires_source_type(source_type_code, request_type_code) values('idVerification', 'cadastreChange');
insert into application.request_type_requires_source_type(source_type_code, request_type_code) values('sitePlan', 'redefineCadastre');
insert into application.request_type_requires_source_type(source_type_code, request_type_code) values('idVerification', 'redefineCadastre');
insert into application.request_type_requires_source_type(source_type_code, request_type_code) values('reqFromSurveor', 'smd-regnr');
insert into application.request_type_requires_source_type(source_type_code, request_type_code) values('idVerification', 'smd-regnr');



--Table application.application_status_type ----
DROP TABLE IF EXISTS application.application_status_type CASCADE;
CREATE TABLE application.application_status_type(
    code varchar(50) NOT NULL,
    display_value varchar(250) NOT NULL,
    is_terminal bool NOT NULL DEFAULT (false),
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),
    office_code varchar(40) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT application_status_type_pkey PRIMARY KEY (code)
);


comment on table application.application_status_type is 'The list of potential statuses an application can get.';
    
 -- Data for the table application.application_status_type -- 
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-regnr-received', 'Received', false, 'c', 'csau');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-plancertification-received', 'Received', false, 'c', 'csau');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-cadchange-submit', 'Submit', false, 'c', 'csau');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-cadredef-submit', 'Submit', false, 'c', 'csau');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-regnr-completed', 'Completed', true, 'c', 'archive');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-cadchange-make-changes', 'Make Changes', false, 'c', 'cartographic-gis-section');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-cadredef-make-changes', 'Make Changes', false, 'c', 'cartographic-gis-section');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-cadchange-completed', 'Completed', true, 'c', 'archive');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-cadredef-completed', 'Completed', true, 'c', 'archive');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-cadchange-cancelled', 'Cancelled', true, 'c', 'archive');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-cadredef-cancelled', 'Cancelled', true, 'c', 'archive');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-plancertification-completed', 'Completed', true, 'c', 'archive');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-plancertification-cancelled', 'Cancelled', true, 'c', 'archive');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-regnr-vetted', 'Vetted', false, 'c', 'csau');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-regnr-paid', 'Paid', false, 'c', 'smd-registry');
insert into application.application_status_type(code, display_value, is_terminal, status, office_code) values('smd-regnr-rejected', 'Rejected', true, 'c', 'archive');



--Table document.document ----
DROP TABLE IF EXISTS document.document CASCADE;
CREATE TABLE document.document(
    id varchar(40) NOT NULL,
    nr varchar(15) NOT NULL,
    extension varchar(5) NOT NULL,
    body bytea NOT NULL,
    description varchar(100),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT document_nr_unique UNIQUE (nr),
    CONSTRAINT document_pkey PRIMARY KEY (id)
);



-- Index document_index_on_rowidentifier  --
CREATE INDEX document_index_on_rowidentifier ON document.document (rowidentifier);
    

comment on table document.document is 'An extension of the source table to contain the image files of scanned documents forming part of the land office archive including the paper documents presented or created through cadastre or registration processes
LADM Reference Object
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
DROP TRIGGER IF EXISTS __track_changes ON document.document CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON document.document FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table document.document_historic used for the history of data of table document.document ---
DROP TABLE IF EXISTS document.document_historic CASCADE;
CREATE TABLE document.document_historic
(
    id varchar(40),
    nr varchar(15),
    extension varchar(5),
    body bytea,
    description varchar(100),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index document_historic_index_on_rowidentifier  --
CREATE INDEX document_historic_index_on_rowidentifier ON document.document_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON document.document CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON document.document FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table system.setting ----
DROP TABLE IF EXISTS system.setting CASCADE;
CREATE TABLE system.setting(
    name varchar(50) NOT NULL,
    vl varchar(2000) NOT NULL,
    active bool NOT NULL DEFAULT (true),
    description varchar(555) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT setting_pkey PRIMARY KEY (name)
);


comment on table system.setting is 'Global settings for the FLOSS SOLA application
LADM Reference Object
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
 -- Data for the table system.setting -- 
insert into system.setting(name, vl, active, description) values('map-srid', '32630', true, 'The srid of the geographic data that are administered in the system.');
insert into system.setting(name, vl, active, description) values('map-west', '807000', true, 'The most west coordinate. It is used in the map control.');
insert into system.setting(name, vl, active, description) values('map-south', '612400', true, 'The most south coordinate. It is used in the map control.');
insert into system.setting(name, vl, active, description) values('map-east', '816600', true, 'The most east coordinate. It is used in the map control.');
insert into system.setting(name, vl, active, description) values('map-north', '622000', true, 'The most north coordinate. It is used in the map control.');
insert into system.setting(name, vl, active, description) values('map-tolerance', '0.01', true, 'The tolerance that is used while snapping geometries to each other. If two points are within this distance are considered being in the same location.');
insert into system.setting(name, vl, active, description) values('map-shift-tolerance-rural', '20', true, 'The shift tolerance of boundary points used in cadastre change in rural areas.');
insert into system.setting(name, vl, active, description) values('map-shift-tolerance-urban', '5', true, 'The shift tolerance of boundary points used in cadastre change in urban areas.');
insert into system.setting(name, vl, active, description) values('current-region', 'GA', true, 'Ghana extension: The current region recognized from the application.');



--Table system.appuser_setting ----
DROP TABLE IF EXISTS system.appuser_setting CASCADE;
CREATE TABLE system.appuser_setting(
    user_id varchar(40) NOT NULL,
    name varchar(50) NOT NULL,
    vl varchar(2000) NOT NULL,
    active bool NOT NULL DEFAULT (true),

    -- Internal constraints
    
    CONSTRAINT appuser_setting_pkey PRIMARY KEY (user_id,name)
);


comment on table system.appuser_setting is 'Software settings specific for a user within the FLOSS SOLA application
LADM Reference Object
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
--Table system.language ----
DROP TABLE IF EXISTS system.language CASCADE;
CREATE TABLE system.language(
    code varchar(7) NOT NULL,
    display_value varchar(250) NOT NULL,
    active bool NOT NULL DEFAULT (true),
    is_default bool NOT NULL DEFAULT (false),
    item_order integer NOT NULL DEFAULT (1),

    -- Internal constraints
    
    CONSTRAINT language_display_value_unique UNIQUE (display_value),
    CONSTRAINT language_pkey PRIMARY KEY (code)
);


comment on table system.language is 'Thelanguages that can be used within the FLOSS SOLA application.
LADM Reference Object
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
 -- Data for the table system.language -- 
insert into system.language(code, display_value, active, is_default, item_order) values('en-US', 'English', true, true, 1);



--Table system.config_map_layer ----
DROP TABLE IF EXISTS system.config_map_layer CASCADE;
CREATE TABLE system.config_map_layer(
    name varchar(50) NOT NULL,
    title varchar(100) NOT NULL,
    type_code varchar(20) NOT NULL,
    active bool NOT NULL DEFAULT (true),
    visible_in_start bool NOT NULL DEFAULT (true),
    item_order integer NOT NULL DEFAULT (0),
    style varchar(4000),
    url varchar(500),
    wms_layers varchar(500),
    wms_version varchar(10),
    wms_format varchar(15),
    pojo_structure varchar(500),
    pojo_query_name varchar(100),
    pojo_query_name_for_select varchar(100),
    shape_location varchar(500),
    security_user varchar(30),
    security_password varchar(30),

    -- Internal constraints
    
    CONSTRAINT config_map_layer_fields_required CHECK (case when type_code = 'wms' then url is not null and wms_layers is not null when type_code = 'pojo' then pojo_query_name is not null and pojo_structure is not null and style is not null when type_code = 'shape' then shape_location is not null and style is not null end),
    CONSTRAINT config_map_layer_title_unique UNIQUE (title),
    CONSTRAINT config_map_layer_pkey PRIMARY KEY (name)
);


comment on table system.config_map_layer is 'Parameters for defining map layers in FLOSS SOLA gis component
LADM Reference Object
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
 -- Data for the table system.config_map_layer -- 
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name, pojo_query_name_for_select) values('parcels', 'Parcels', 'pojo', true, true, 20, 'parcel.xml', 'theGeom:Polygon,label:""', 'SpatialResult.getParcels', 'dynamic.informationtool.get_parcel');
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name, pojo_query_name_for_select) values('pending-parcels', 'Pending parcels', 'pojo', true, true, 30, 'pending_parcels.xml', 'theGeom:Polygon,label:""', 'SpatialResult.getParcelsPending', 'dynamic.informationtool.get_parcel_pending');
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name, pojo_query_name_for_select) values('applications', 'Applications', 'pojo', true, true, 70, 'application.xml', 'theGeom:MultiPoint,label:""', 'SpatialResult.getApplications', 'dynamic.informationtool.get_application');
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name, pojo_query_name_for_select) values('parcels-historic-current-ba', 'Historic parcels with current titles', 'pojo', true, true, 10, 'parcel_historic_current_ba.xml', 'theGeom:Polygon,label:""', 'SpatialResult.getParcelsHistoricWithCurrentBA', 'dynamic.informationtool.get_parcel_historic_current_ba');
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name, pojo_query_name_for_select) values('regions', 'Regions', 'pojo', true, true, 80, 'region.xml', 'theGeom:Polygon,label:""', 'SpatialResult.getRegion', 'dynamic.informationtool.get_region');
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name, pojo_query_name_for_select) values('districts', 'Districts', 'pojo', true, true, 90, 'district.xml', 'theGeom:Polygon,label:""', 'SpatialResult.getDistrict', 'dynamic.informationtool.get_district');
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name, pojo_query_name_for_select) values('sections', 'Sections', 'pojo', true, true, 100, 'section.xml', 'theGeom:Polygon,label:""', 'SpatialResult.getSection', 'dynamic.informationtool.get_section');
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name, pojo_query_name_for_select) values('blocks', 'Blocks', 'pojo', true, true, 110, 'block.xml', 'theGeom:Polygon,label:""', 'SpatialResult.getBlock', 'dynamic.informationtool.get_block');
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name, pojo_query_name_for_select) values('buildings', 'Buildings', 'pojo', true, true, 120, 'building.xml', 'theGeom:Polygon,label:""', 'SpatialResult.getBuildings', 'dynamic.informationtool.get_building');
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name, pojo_query_name_for_select) values('allodials', 'Allodials', 'pojo', true, true, 130, 'allodial.xml', 'theGeom:Polygon,label:""', 'SpatialResult.getAllodials', 'dynamic.informationtool.get_allodial');
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name) values('parcel-nodes', 'Parcel nodes', 'pojo', true, true, 40, 'parcel_node.xml', 'theGeom:Polygon,label:""', 'SpatialResult.getParcelNodes');
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name) values('parcel-pending-completed', 'Parcels with plan certification completed', 'pojo', true, true, 33, 'pending_parcels_completed.xml', 'theGeom:Polygon,label:""', 'SpatialResult.getParcelPendingCompleted');
insert into system.config_map_layer(name, title, type_code, active, visible_in_start, item_order, style, pojo_structure, pojo_query_name) values('parcel-pending-inprogress', 'Parcels with plan certification in progress', 'pojo', true, true, 35, 'pending_parcels_inprogress.xml', 'theGeom:Polygon,label:""', 'SpatialResult.getParcelPendingInProgress');



--Table system.config_map_layer_type ----
DROP TABLE IF EXISTS system.config_map_layer_type CASCADE;
CREATE TABLE system.config_map_layer_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL,
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT config_map_layer_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT config_map_layer_type_pkey PRIMARY KEY (code)
);


comment on table system.config_map_layer_type is 'Parameters for defining categories/types of map layers in FLOSS SOLA gis component
LADM Reference Object 
FLOSS SOLA Extension
LADM Definition
Not Applicable';
    
 -- Data for the table system.config_map_layer_type -- 
insert into system.config_map_layer_type(code, display_value, status) values('wms', 'WMS server with layers::::Server WMS con layer', 'c');
insert into system.config_map_layer_type(code, display_value, status) values('shape', 'Shapefile::::Shapefile', 'c');
insert into system.config_map_layer_type(code, display_value, status) values('pojo', 'Pojo layer::::Pojo layer', 'c');



--Table administrative.ba_unit_as_party ----
DROP TABLE IF EXISTS administrative.ba_unit_as_party CASCADE;
CREATE TABLE administrative.ba_unit_as_party(
    ba_unit_id varchar(40) NOT NULL,
    party_id varchar(40) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT ba_unit_as_party_pkey PRIMARY KEY (ba_unit_id,party_id)
);


comment on table administrative.ba_unit_as_party is 'LADM Definition
LA_BAUnit is associated to class LA_Party (a party may be an basic administrative unit, indicated by the attribute ‘partyType’).

LADM Reference Object
Association baunitAsParty';
    
--Table transaction.reg_status_type ----
DROP TABLE IF EXISTS transaction.reg_status_type CASCADE;
CREATE TABLE transaction.reg_status_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT reg_status_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT reg_status_type_pkey PRIMARY KEY (code)
);


comment on table transaction.reg_status_type is 'This table has the list of statuses that a registration about Rights/Restrictions/ Responsabilities/ Cadastral objects / Sources can have.	';
    
 -- Data for the table transaction.reg_status_type -- 
insert into transaction.reg_status_type(code, display_value, status) values('current', 'Current', 'c');
insert into transaction.reg_status_type(code, display_value, status) values('pending', 'Pending', 'c');
insert into transaction.reg_status_type(code, display_value, status) values('historic', 'Historic', 'c');
insert into transaction.reg_status_type(code, display_value, status) values('previous', 'Previous', 'c');



--Table system.br ----
DROP TABLE IF EXISTS system.br CASCADE;
CREATE TABLE system.br(
    id varchar(100) NOT NULL,
    display_name varchar(250) NOT NULL DEFAULT (uuid_generate_v1()),
    technical_type_code varchar(20) NOT NULL,
    feedback varchar(2000),
    description varchar(1000),
    technical_description varchar(1000),

    -- Internal constraints
    
    CONSTRAINT br_display_name_unique UNIQUE (display_name),
    CONSTRAINT br_pkey PRIMARY KEY (id)
);


comment on table system.br is 'In this table there are defined the business rules that are used in the system.';
    
--Table system.br_technical_type ----
DROP TABLE IF EXISTS system.br_technical_type CASCADE;
CREATE TABLE system.br_technical_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL,
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT br_technical_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT br_technical_type_pkey PRIMARY KEY (code)
);


comment on table system.br_technical_type is 'Here are specified the types of techincal implementations of the business rule.';
    
 -- Data for the table system.br_technical_type -- 
insert into system.br_technical_type(code, display_value, status, description) values('sql', 'SQL::::SQL', 'c', 'The rule definition is based in sql and it is executed by the database engine.');
insert into system.br_technical_type(code, display_value, status, description) values('drools', 'Drools::::Drools', 'c', 'The rule definition is based on Drools engine.');



--Table system.br_validation ----
DROP TABLE IF EXISTS system.br_validation CASCADE;
CREATE TABLE system.br_validation(
    id varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    br_id varchar(100) NOT NULL,
    target_code varchar(20) NOT NULL,
    target_action_type_code varchar(50),
    target_reg_moment varchar(20),
    target_request_type_code varchar(50),
    target_rrr_type_code varchar(20),
    target_operation_code varchar(20),
    severity_code varchar(20) NOT NULL,
    order_of_execution integer NOT NULL DEFAULT (0),

    -- Internal constraints
    
    CONSTRAINT br_validation_action_moment_unique UNIQUE (br_id, target_code, target_action_type_code),
    CONSTRAINT br_validation_reg_moment_unique UNIQUE (br_id, target_code, target_reg_moment),
    CONSTRAINT br_validation_pkey PRIMARY KEY (id)
);


comment on table system.br_validation is 'In this table are defined the sets of rules that has to be executed.
If for a rule there is not target moment specified, then the rule will not be part of the set.';
    
--Table system.br_definition ----
DROP TABLE IF EXISTS system.br_definition CASCADE;
CREATE TABLE system.br_definition(
    br_id varchar(100) NOT NULL,
    active_from date NOT NULL,
    active_until date NOT NULL DEFAULT ('infinity'),
    body varchar(4000) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT br_definition_pkey PRIMARY KEY (br_id,active_from)
);


comment on table system.br_definition is '';
    
--Table system.br_severity_type ----
DROP TABLE IF EXISTS system.br_severity_type CASCADE;
CREATE TABLE system.br_severity_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL,
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT br_severity_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT br_severity_type_pkey PRIMARY KEY (code)
);


comment on table system.br_severity_type is 'These are the types of severity of the business rules within the context of there use.';
    
 -- Data for the table system.br_severity_type -- 
insert into system.br_severity_type(code, display_value, status) values('critical', 'Critical', 'c');
insert into system.br_severity_type(code, display_value, status) values('medium', 'Medium', 'c');
insert into system.br_severity_type(code, display_value, status) values('warning', 'Warning', 'c');



--Table system.br_validation_target_type ----
DROP TABLE IF EXISTS system.br_validation_target_type CASCADE;
CREATE TABLE system.br_validation_target_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL,
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT br_validation_target_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT br_validation_target_type_pkey PRIMARY KEY (code)
);


comment on table system.br_validation_target_type is 'The potential targets of the validation rules.';
    
 -- Data for the table system.br_validation_target_type -- 
insert into system.br_validation_target_type(code, display_value, status, description) values('application-action', 'Application action::::ITALIANO', 'c', 'The target of the validation is the application action. It accepts one parameter {id} which is the application action id.');
insert into system.br_validation_target_type(code, display_value, status, description) values('rrr', 'Right or Restriction::::ITALIANO', 'c', 'The target of the validation is the rrr. It accepts one parameter {id} which is the rrr id. ');
insert into system.br_validation_target_type(code, display_value, status, description) values('ba_unit', 'Administrative Unit::::ITALIANO', 'c', 'The target of the validation is the ba_unit. It accepts one parameter {id} which is the ba_unit id.');
insert into system.br_validation_target_type(code, display_value, status, description) values('source', 'Source::::ITALIANO', 'c', 'The target of the validation is the source. It accepts one parameter {id} which is the source id.');
insert into system.br_validation_target_type(code, display_value, status, description) values('cadastre_object', 'Cadastre Object::::ITALIANO', 'c', 'The target of the validation is the transaction related with the cadastre change. It accepts one parameter {id} which is the transaction id.');
insert into system.br_validation_target_type(code, display_value, status, description) values('application', 'Application', 'c', 'The target of the validation is the application. It accepts one parameter {id} which is the application id.');



--Table cadastre.cadastre_object_type ----
DROP TABLE IF EXISTS cadastre.cadastre_object_type CASCADE;
CREATE TABLE cadastre.cadastre_object_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL,
    in_topology bool NOT NULL DEFAULT (false),

    -- Internal constraints
    
    CONSTRAINT cadastre_object_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT cadastre_object_type_pkey PRIMARY KEY (code)
);


comment on table cadastre.cadastre_object_type is 'The type of spatial object. This defines the specialisation of the spatial unit. It can be a parcel, building_unit or backgroup data like a road etc.';
    
 -- Data for the table cadastre.cadastre_object_type -- 
insert into cadastre.cadastre_object_type(code, display_value, status, in_topology) values('parcel', 'Parcel', 'c', true);
insert into cadastre.cadastre_object_type(code, display_value, status, in_topology) values('building', 'Building', 'c', false);
insert into cadastre.cadastre_object_type(code, display_value, status, in_topology) values('strata', 'Strata', 'c', false);
insert into cadastre.cadastre_object_type(code, display_value, status, in_topology) values('allodial', 'Allodial', 'c', true);



--Table cadastre.cadastre_object ----
DROP TABLE IF EXISTS cadastre.cadastre_object CASCADE;
CREATE TABLE cadastre.cadastre_object(
    id varchar(40) NOT NULL,
    type_code varchar(20) NOT NULL DEFAULT ('parcel'),
    building_unit_type_code varchar(20),
    approval_datetime timestamp,
    historic_datetime timestamp,
    source_reference varchar(100),
    name_firstpart varchar(40) NOT NULL,
    name_lastpart varchar(50) NOT NULL,
    status_code varchar(20) NOT NULL DEFAULT ('pending'),
    geom_polygon GEOMETRY
        CONSTRAINT enforce_dims_geom_polygon CHECK (st_ndims(geom_polygon) = 2),
        CONSTRAINT enforce_srid_geom_polygon CHECK (st_srid(geom_polygon) = 32630),
        CONSTRAINT enforce_valid_geom_polygon CHECK (st_isvalid(geom_polygon)),
        CONSTRAINT enforce_geotype_geom_polygon CHECK (geometrytype(geom_polygon) = 'POLYGON'::text OR geom_polygon IS NULL),
    transaction_id varchar(40) NOT NULL,
    upn varchar(30),
    description varchar(200),
    legacy_lot_nr varchar(20),
    legacy_property_nr varchar(20),
    found_in_cadastre_object_id varchar(40),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT cadastre_object_name UNIQUE (name_firstpart, name_lastpart),
    CONSTRAINT cadastre_object_pkey PRIMARY KEY (id)
);



-- Index cadastre_object_index_on_geom_polygon  --
CREATE INDEX cadastre_object_index_on_geom_polygon ON cadastre.cadastre_object using gist(geom_polygon);
    
-- Index cadastre_object_index_on_rowidentifier  --
CREATE INDEX cadastre_object_index_on_rowidentifier ON cadastre.cadastre_object (rowidentifier);
    

comment on table cadastre.cadastre_object is '';
    
DROP TRIGGER IF EXISTS __track_changes ON cadastre.cadastre_object CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON cadastre.cadastre_object FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table cadastre.cadastre_object_historic used for the history of data of table cadastre.cadastre_object ---
DROP TABLE IF EXISTS cadastre.cadastre_object_historic CASCADE;
CREATE TABLE cadastre.cadastre_object_historic
(
    id varchar(40),
    type_code varchar(20),
    building_unit_type_code varchar(20),
    approval_datetime timestamp,
    historic_datetime timestamp,
    source_reference varchar(100),
    name_firstpart varchar(40),
    name_lastpart varchar(50),
    status_code varchar(20),
    geom_polygon GEOMETRY
        CONSTRAINT enforce_dims_geom_polygon CHECK (st_ndims(geom_polygon) = 2),
        CONSTRAINT enforce_srid_geom_polygon CHECK (st_srid(geom_polygon) = 32630),
        CONSTRAINT enforce_valid_geom_polygon CHECK (st_isvalid(geom_polygon)),
        CONSTRAINT enforce_geotype_geom_polygon CHECK (geometrytype(geom_polygon) = 'POLYGON'::text OR geom_polygon IS NULL),
    transaction_id varchar(40),
    upn varchar(30),
    description varchar(200),
    legacy_lot_nr varchar(20),
    legacy_property_nr varchar(20),
    found_in_cadastre_object_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index cadastre_object_historic_index_on_geom_polygon  --
CREATE INDEX cadastre_object_historic_index_on_geom_polygon ON cadastre.cadastre_object_historic using gist(geom_polygon);
    
-- Index cadastre_object_historic_index_on_rowidentifier  --
CREATE INDEX cadastre_object_historic_index_on_rowidentifier ON cadastre.cadastre_object_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON cadastre.cadastre_object CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON cadastre.cadastre_object FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table administrative.ba_unit_rel_type ----
DROP TABLE IF EXISTS administrative.ba_unit_rel_type CASCADE;
CREATE TABLE administrative.ba_unit_rel_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT ba_unit_rel_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT ba_unit_rel_type_pkey PRIMARY KEY (code)
);


comment on table administrative.ba_unit_rel_type is 'The types of relation two ba_units can have between each other.';
    
 -- Data for the table administrative.ba_unit_rel_type -- 
insert into administrative.ba_unit_rel_type(code, display_value, description, status) values('priorTitle', 'Prior Title', 'Prior Title', 'c');
insert into administrative.ba_unit_rel_type(code, display_value, description, status) values('rootTitle', 'Root of Title', 'Root of Title', 'c');



--Table administrative.notation ----
DROP TABLE IF EXISTS administrative.notation CASCADE;
CREATE TABLE administrative.notation(
    id varchar(40) NOT NULL,
    ba_unit_id varchar(40),
    rrr_id varchar(40),
    transaction_id varchar(40) NOT NULL,
    reference_nr varchar(15) NOT NULL,
    notation_text varchar(1000),
    status_code varchar(20) NOT NULL DEFAULT ('pending'),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT notation_pkey PRIMARY KEY (id)
);



-- Index notation_index_on_rowidentifier  --
CREATE INDEX notation_index_on_rowidentifier ON administrative.notation (rowidentifier);
    

comment on table administrative.notation is 'All notations related with a baunit are maintained here. Every notation gets a reference number and it is always associated with a transaction.';
    
DROP TRIGGER IF EXISTS __track_changes ON administrative.notation CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON administrative.notation FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table administrative.notation_historic used for the history of data of table administrative.notation ---
DROP TABLE IF EXISTS administrative.notation_historic CASCADE;
CREATE TABLE administrative.notation_historic
(
    id varchar(40),
    ba_unit_id varchar(40),
    rrr_id varchar(40),
    transaction_id varchar(40),
    reference_nr varchar(15),
    notation_text varchar(1000),
    status_code varchar(20),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index notation_historic_index_on_rowidentifier  --
CREATE INDEX notation_historic_index_on_rowidentifier ON administrative.notation_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON administrative.notation CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON administrative.notation FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table administrative.ba_unit_area ----
DROP TABLE IF EXISTS administrative.ba_unit_area CASCADE;
CREATE TABLE administrative.ba_unit_area(
    id varchar(40) NOT NULL,
    ba_unit_id varchar(40) NOT NULL,
    type_code varchar(20) NOT NULL,
    size numeric(19, 2) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT ba_unit_area_pkey PRIMARY KEY (id)
);



-- Index ba_unit_area_index_on_rowidentifier  --
CREATE INDEX ba_unit_area_index_on_rowidentifier ON administrative.ba_unit_area (rowidentifier);
    

comment on table administrative.ba_unit_area is '';
    
DROP TRIGGER IF EXISTS __track_changes ON administrative.ba_unit_area CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON administrative.ba_unit_area FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table administrative.ba_unit_area_historic used for the history of data of table administrative.ba_unit_area ---
DROP TABLE IF EXISTS administrative.ba_unit_area_historic CASCADE;
CREATE TABLE administrative.ba_unit_area_historic
(
    id varchar(40),
    ba_unit_id varchar(40),
    type_code varchar(20),
    size numeric(19, 2),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index ba_unit_area_historic_index_on_rowidentifier  --
CREATE INDEX ba_unit_area_historic_index_on_rowidentifier ON administrative.ba_unit_area_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON administrative.ba_unit_area CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON administrative.ba_unit_area FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table administrative.rrr_share ----
DROP TABLE IF EXISTS administrative.rrr_share CASCADE;
CREATE TABLE administrative.rrr_share(
    rrr_id varchar(40) NOT NULL,
    id varchar(40) NOT NULL,
    nominator smallint NOT NULL,
    denominator smallint NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT rrr_share_pkey PRIMARY KEY (rrr_id,id)
);



-- Index rrr_share_index_on_rowidentifier  --
CREATE INDEX rrr_share_index_on_rowidentifier ON administrative.rrr_share (rowidentifier);
    

comment on table administrative.rrr_share is 'If parties are involved in an rrr then they partecipate in shares. There is at least one share for each rrr.
LADM Reference Object 
LA_RRR.share';
    
DROP TRIGGER IF EXISTS __track_changes ON administrative.rrr_share CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON administrative.rrr_share FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table administrative.rrr_share_historic used for the history of data of table administrative.rrr_share ---
DROP TABLE IF EXISTS administrative.rrr_share_historic CASCADE;
CREATE TABLE administrative.rrr_share_historic
(
    rrr_id varchar(40),
    id varchar(40),
    nominator smallint,
    denominator smallint,
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index rrr_share_historic_index_on_rowidentifier  --
CREATE INDEX rrr_share_historic_index_on_rowidentifier ON administrative.rrr_share_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON administrative.rrr_share CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON administrative.rrr_share FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table administrative.party_for_rrr ----
DROP TABLE IF EXISTS administrative.party_for_rrr CASCADE;
CREATE TABLE administrative.party_for_rrr(
    rrr_id varchar(40) NOT NULL,
    party_id varchar(40) NOT NULL,
    share_id varchar(40),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT party_for_rrr_pkey PRIMARY KEY (rrr_id,party_id)
);



-- Index party_for_rrr_index_on_rowidentifier  --
CREATE INDEX party_for_rrr_index_on_rowidentifier ON administrative.party_for_rrr (rowidentifier);
    

comment on table administrative.party_for_rrr is 'There may be parties involved in an RRR. Parties can be involved also in Shares.';
    
DROP TRIGGER IF EXISTS __track_changes ON administrative.party_for_rrr CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON administrative.party_for_rrr FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table administrative.party_for_rrr_historic used for the history of data of table administrative.party_for_rrr ---
DROP TABLE IF EXISTS administrative.party_for_rrr_historic CASCADE;
CREATE TABLE administrative.party_for_rrr_historic
(
    rrr_id varchar(40),
    party_id varchar(40),
    share_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index party_for_rrr_historic_index_on_rowidentifier  --
CREATE INDEX party_for_rrr_historic_index_on_rowidentifier ON administrative.party_for_rrr_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON administrative.party_for_rrr CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON administrative.party_for_rrr FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table transaction.transaction ----
DROP TABLE IF EXISTS transaction.transaction CASCADE;
CREATE TABLE transaction.transaction(
    id varchar(40) NOT NULL,
    from_application_id varchar(40),
    status_code varchar(20) NOT NULL DEFAULT ('pending'),
    approval_datetime timestamp,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT transaction_from_application_id_unique UNIQUE (from_application_id),
    CONSTRAINT transaction_pkey PRIMARY KEY (id)
);



-- Index transaction_index_on_rowidentifier  --
CREATE INDEX transaction_index_on_rowidentifier ON transaction.transaction (rowidentifier);
    

comment on table transaction.transaction is 'Changes in the system come by transactions. A transaction is initiated (optionally) by a service. By introducing the concept of transaction it can be traced how the changes in the administrative schema came. Also by approving the transaction we can approve changes or by rejecting a transaction we can remove the pending changes that came with it and restore the previous state of the administrative schema.';
    
DROP TRIGGER IF EXISTS __track_changes ON transaction.transaction CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON transaction.transaction FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table transaction.transaction_historic used for the history of data of table transaction.transaction ---
DROP TABLE IF EXISTS transaction.transaction_historic CASCADE;
CREATE TABLE transaction.transaction_historic
(
    id varchar(40),
    from_application_id varchar(40),
    status_code varchar(20),
    approval_datetime timestamp,
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index transaction_historic_index_on_rowidentifier  --
CREATE INDEX transaction_historic_index_on_rowidentifier ON transaction.transaction_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON transaction.transaction CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON transaction.transaction FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table transaction.transaction_status_type ----
DROP TABLE IF EXISTS transaction.transaction_status_type CASCADE;
CREATE TABLE transaction.transaction_status_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT transaction_status_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT transaction_status_type_pkey PRIMARY KEY (code)
);


comment on table transaction.transaction_status_type is 'This table has the list of statuses that a transaction can take.
Potential values are current, pending, rejected.';
    
 -- Data for the table transaction.transaction_status_type -- 
insert into transaction.transaction_status_type(code, display_value, status) values('approved', 'Approved::::Approvata', 'c');
insert into transaction.transaction_status_type(code, display_value, status) values('cancelled', 'CancelledApproved::::Cancellata', 'c');
insert into transaction.transaction_status_type(code, display_value, status) values('pending', 'Pending::::In Attesa', 'c');
insert into transaction.transaction_status_type(code, display_value, status) values('completed', 'Completed::::ITALIANO', 'c');



--Table application.type_action ----
DROP TABLE IF EXISTS application.type_action CASCADE;
CREATE TABLE application.type_action(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('t'),

    -- Internal constraints
    
    CONSTRAINT type_action_display_value_unique UNIQUE (display_value),
    CONSTRAINT type_action_pkey PRIMARY KEY (code)
);


comment on table application.type_action is 'This is the coded list of allowed operations on rrr and ba_unit. Present values are: new, remove, vary.';
    
 -- Data for the table application.type_action -- 
insert into application.type_action(code, display_value, status) values('new', 'New::::ITALIANO', 'c');
insert into application.type_action(code, display_value, status) values('vary', 'Vary::::ITALIANO', 'c');
insert into application.type_action(code, display_value, status) values('cancel', 'Cancel::::ITALIANO', 'c');



--Table cadastre.cadastre_object_target ----
DROP TABLE IF EXISTS cadastre.cadastre_object_target CASCADE;
CREATE TABLE cadastre.cadastre_object_target(
    transaction_id varchar(40) NOT NULL,
    cadastre_object_id varchar(40) NOT NULL,
    geom_polygon GEOMETRY
        CONSTRAINT enforce_dims_geom_polygon CHECK (st_ndims(geom_polygon) = 2),
        CONSTRAINT enforce_srid_geom_polygon CHECK (st_srid(geom_polygon) = 32630),
        CONSTRAINT enforce_valid_geom_polygon CHECK (st_isvalid(geom_polygon)),
        CONSTRAINT enforce_geotype_geom_polygon CHECK (geometrytype(geom_polygon) = 'POLYGON'::text OR geom_polygon IS NULL),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT cadastre_object_target_pkey PRIMARY KEY (transaction_id,cadastre_object_id)
);



-- Index cadastre_object_target_index_on_geom_polygon  --
CREATE INDEX cadastre_object_target_index_on_geom_polygon ON cadastre.cadastre_object_target using gist(geom_polygon);
    
-- Index cadastre_object_target_index_on_rowidentifier  --
CREATE INDEX cadastre_object_target_index_on_rowidentifier ON cadastre.cadastre_object_target (rowidentifier);
    

comment on table cadastre.cadastre_object_target is 'This is a cadastre object that is a target of a cadastre related transaction. If the transaction is not yet approved or cancelled, the cadastre object gets a pending status.';
    
DROP TRIGGER IF EXISTS __track_changes ON cadastre.cadastre_object_target CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON cadastre.cadastre_object_target FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table cadastre.cadastre_object_target_historic used for the history of data of table cadastre.cadastre_object_target ---
DROP TABLE IF EXISTS cadastre.cadastre_object_target_historic CASCADE;
CREATE TABLE cadastre.cadastre_object_target_historic
(
    transaction_id varchar(40),
    cadastre_object_id varchar(40),
    geom_polygon GEOMETRY
        CONSTRAINT enforce_dims_geom_polygon CHECK (st_ndims(geom_polygon) = 2),
        CONSTRAINT enforce_srid_geom_polygon CHECK (st_srid(geom_polygon) = 32630),
        CONSTRAINT enforce_valid_geom_polygon CHECK (st_isvalid(geom_polygon)),
        CONSTRAINT enforce_geotype_geom_polygon CHECK (geometrytype(geom_polygon) = 'POLYGON'::text OR geom_polygon IS NULL),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index cadastre_object_target_historic_index_on_geom_polygon  --
CREATE INDEX cadastre_object_target_historic_index_on_geom_polygon ON cadastre.cadastre_object_target_historic using gist(geom_polygon);
    
-- Index cadastre_object_target_historic_index_on_rowidentifier  --
CREATE INDEX cadastre_object_target_historic_index_on_rowidentifier ON cadastre.cadastre_object_target_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON cadastre.cadastre_object_target CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON cadastre.cadastre_object_target FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table party.gender_type ----
DROP TABLE IF EXISTS party.gender_type CASCADE;
CREATE TABLE party.gender_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT gender_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT gender_type_pkey PRIMARY KEY (code)
);


comment on table party.gender_type is 'The gender type list a party can have.';
    
 -- Data for the table party.gender_type -- 
insert into party.gender_type(code, display_value, status) values('male', 'Male', 'c');
insert into party.gender_type(code, display_value, status) values('female', 'Female', 'c');



--Table cadastre.survey_point ----
DROP TABLE IF EXISTS cadastre.survey_point CASCADE;
CREATE TABLE cadastre.survey_point(
    transaction_id varchar(40) NOT NULL,
    id varchar(40) NOT NULL,
    boundary bool NOT NULL DEFAULT (true),
    geom GEOMETRY NOT NULL
        CONSTRAINT enforce_dims_geom CHECK (st_ndims(geom) = 2),
        CONSTRAINT enforce_srid_geom CHECK (st_srid(geom) = 32630),
        CONSTRAINT enforce_valid_geom CHECK (st_isvalid(geom)),
        CONSTRAINT enforce_geotype_geom CHECK (geometrytype(geom) = 'POINT'::text OR geom IS NULL),
    original_geom GEOMETRY NOT NULL
        CONSTRAINT enforce_dims_original_geom CHECK (st_ndims(original_geom) = 2),
        CONSTRAINT enforce_srid_original_geom CHECK (st_srid(original_geom) = 32630),
        CONSTRAINT enforce_valid_original_geom CHECK (st_isvalid(original_geom)),
        CONSTRAINT enforce_geotype_original_geom CHECK (geometrytype(original_geom) = 'POINT'::text OR original_geom IS NULL),
    linked bool NOT NULL DEFAULT (false),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT survey_point_pkey PRIMARY KEY (transaction_id,id)
);



-- Index survey_point_index_on_geom  --
CREATE INDEX survey_point_index_on_geom ON cadastre.survey_point using gist(geom);
    
-- Index survey_point_index_on_original_geom  --
CREATE INDEX survey_point_index_on_original_geom ON cadastre.survey_point using gist(original_geom);
    
-- Index survey_point_index_on_rowidentifier  --
CREATE INDEX survey_point_index_on_rowidentifier ON cadastre.survey_point (rowidentifier);
    

comment on table cadastre.survey_point is '';
    
DROP TRIGGER IF EXISTS __track_changes ON cadastre.survey_point CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON cadastre.survey_point FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table cadastre.survey_point_historic used for the history of data of table cadastre.survey_point ---
DROP TABLE IF EXISTS cadastre.survey_point_historic CASCADE;
CREATE TABLE cadastre.survey_point_historic
(
    transaction_id varchar(40),
    id varchar(40),
    boundary bool,
    geom GEOMETRY
        CONSTRAINT enforce_dims_geom CHECK (st_ndims(geom) = 2),
        CONSTRAINT enforce_srid_geom CHECK (st_srid(geom) = 32630),
        CONSTRAINT enforce_valid_geom CHECK (st_isvalid(geom)),
        CONSTRAINT enforce_geotype_geom CHECK (geometrytype(geom) = 'POINT'::text OR geom IS NULL),
    original_geom GEOMETRY
        CONSTRAINT enforce_dims_original_geom CHECK (st_ndims(original_geom) = 2),
        CONSTRAINT enforce_srid_original_geom CHECK (st_srid(original_geom) = 32630),
        CONSTRAINT enforce_valid_original_geom CHECK (st_isvalid(original_geom)),
        CONSTRAINT enforce_geotype_original_geom CHECK (geometrytype(original_geom) = 'POINT'::text OR original_geom IS NULL),
    linked bool,
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index survey_point_historic_index_on_geom  --
CREATE INDEX survey_point_historic_index_on_geom ON cadastre.survey_point_historic using gist(geom);
    
-- Index survey_point_historic_index_on_original_geom  --
CREATE INDEX survey_point_historic_index_on_original_geom ON cadastre.survey_point_historic using gist(original_geom);
    
-- Index survey_point_historic_index_on_rowidentifier  --
CREATE INDEX survey_point_historic_index_on_rowidentifier ON cadastre.survey_point_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON cadastre.survey_point CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON cadastre.survey_point FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table transaction.transaction_source ----
DROP TABLE IF EXISTS transaction.transaction_source CASCADE;
CREATE TABLE transaction.transaction_source(
    transaction_id varchar(40) NOT NULL,
    source_id varchar(40) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT transaction_source_pkey PRIMARY KEY (transaction_id,source_id)
);



-- Index transaction_source_index_on_rowidentifier  --
CREATE INDEX transaction_source_index_on_rowidentifier ON transaction.transaction_source (rowidentifier);
    

comment on table transaction.transaction_source is '';
    
DROP TRIGGER IF EXISTS __track_changes ON transaction.transaction_source CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON transaction.transaction_source FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table transaction.transaction_source_historic used for the history of data of table transaction.transaction_source ---
DROP TABLE IF EXISTS transaction.transaction_source_historic CASCADE;
CREATE TABLE transaction.transaction_source_historic
(
    transaction_id varchar(40),
    source_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index transaction_source_historic_index_on_rowidentifier  --
CREATE INDEX transaction_source_historic_index_on_rowidentifier ON transaction.transaction_source_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON transaction.transaction_source CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON transaction.transaction_source FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table system.approle ----
DROP TABLE IF EXISTS system.approle CASCADE;
CREATE TABLE system.approle(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL,
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT approle_display_value_unique UNIQUE (display_value),
    CONSTRAINT approle_pkey PRIMARY KEY (code)
);


comment on table system.approle is 'This table contains list of security roles, used to restrict access to the different parts of application, both on server and client side.';
    
 -- Data for the table system.approle -- 
insert into system.approle(code, display_value, status, description) values('DashbrdViewAssign', 'View Assigned Applications', 'c', 'View Assigned Applications in Dashboard');
insert into system.approle(code, display_value, status, description) values('DashbrdViewUnassign', 'View Unassigned Applications', 'c', 'View Unassigned Applications in Dashboard');
insert into system.approle(code, display_value, status, description) values('DashbrdViewOwn', 'View Own Applications', 'c', 'View Applications assigned to user  in Dashboard');
insert into system.approle(code, display_value, status, description) values('ApplnView', 'Search and View Applications', 'c', 'Search and view applications');
insert into system.approle(code, display_value, status, description) values('ApplnCreate', 'Lodge new Applications', 'c', 'Lodge new Applications');
insert into system.approle(code, display_value, status, description) values('ApplnStatus', 'Generate and View Status Report', 'c', 'Generate and View Status Report');
insert into system.approle(code, display_value, status, description) values('ApplnAssignSelf', 'Assign Applications to Self', 'c', 'Able to assign (unassigned) applications to yourself');
insert into system.approle(code, display_value, status, description) values('ApplnUnassignSelf', 'Unassign Applications to Self', 'c', 'Able to unassign (assigned) applications from yourself');
insert into system.approle(code, display_value, status, description) values('ApplnAssignOthers', 'Assign Applications to Other Users', 'c', 'Able to assign (unassigned) applications to other users');
insert into system.approle(code, display_value, status, description) values('ApplnUnassignOthers', 'Unassign Applications to Others', 'c', 'Able to unassign (assigned) applications to other users');
insert into system.approle(code, display_value, status, description) values('StartService', 'Start Service', 'c', 'Start Service');
insert into system.approle(code, display_value, status, description) values('CompleteService', 'Complete Service', 'c', 'Complete Service (prior to approval)');
insert into system.approle(code, display_value, status, description) values('CancelService', 'Cancel Service', 'c', 'Cancel Service');
insert into system.approle(code, display_value, status, description) values('RevertService', 'Revert Service', 'c', 'Revert previously Complete Service');
insert into system.approle(code, display_value, status, description) values('ApplnRequisition', 'Requisition application and request', 'c', 'Request further information from applicant');
insert into system.approle(code, display_value, status, description) values('ApplnResubmit', 'Resubmit Application', 'c', 'Resubmit (requisitioned) application');
insert into system.approle(code, display_value, status, description) values('ApplnApprove', 'Approve Application', 'c', 'Approve Application');
insert into system.approle(code, display_value, status, description) values('ApplnWithdraw', 'Withdraw Application', 'c', 'Applicant withdraws their application');
insert into system.approle(code, display_value, status, description) values('ApplnReject', 'Reject Application', 'c', 'Land Office rejects an application');
insert into system.approle(code, display_value, status, description) values('ApplnValidate', 'Validate Application', 'c', 'User manually runs validation rules for application');
insert into system.approle(code, display_value, status, description) values('ApplnDispatch', 'Dispatch Application', 'c', 'Dispatch any documents to be returned to applicant and any certificates/reports/map prints requested by applicant');
insert into system.approle(code, display_value, status, description) values('ApplnArchive', 'Archive Application', 'c', 'Paper Application File is stored in Land Office Archive');
insert into system.approle(code, display_value, status, description) values('BaunitSave', 'Create or Modify BA Unit', 'c', 'Create or Modify BA Unit (Property)');
insert into system.approle(code, display_value, status, description) values('BauunitrrrSave', 'Create or Modify Rights or Restrictions', 'c', 'Create or Modify Rights or Restrictions');
insert into system.approle(code, display_value, status, description) values('BaunitParcelSave', 'Create or Modify (BA Unit) Parcels', 'c', 'Create or Modify (BA Unit) Parcels');
insert into system.approle(code, display_value, status, description) values('BaunitNotatSave', 'Create or Modify (BA Unit) Notations', 'c', 'Create or Modify (BA Unit) Notations');
insert into system.approle(code, display_value, status, description) values('BaunitCertificate', 'Generate and Print (BA Unit) Certificate', 'c', 'Generate and Print (BA Unit) Certificate');
insert into system.approle(code, display_value, status, description) values('BaunitSearch', 'Search BA Unit', 'c', 'Search BA Unit');
insert into system.approle(code, display_value, status, description) values('TransactionCommit', 'Approve (and Cancel) Transaction', 'c', 'Approve (and Cancel) Transaction');
insert into system.approle(code, display_value, status, description) values('ViewMap', 'View Cadastral Map', 'c', 'View Cadastral Map');
insert into system.approle(code, display_value, status, description) values('PrintMap', 'Print Map', 'c', 'Print Map');
insert into system.approle(code, display_value, status, description) values('ParcelSave', 'Create or modify (Cadastre) Parcel', 'c', 'Create or modify (Cadastre) Parcel');
insert into system.approle(code, display_value, status, description) values('PartySave', 'Create or modify Party', 'c', 'Create or modify Party');
insert into system.approle(code, display_value, status, description) values('SourceSave', 'Create or modify Source', 'c', 'Create or modify Source');
insert into system.approle(code, display_value, status, description) values('SourceSearch', 'Search Sources', 'c', 'Search sources');
insert into system.approle(code, display_value, status, description) values('SourcePrint', 'Print Sources', 'c', 'Print Source');
insert into system.approle(code, display_value, status, description) values('ReportGenerate', 'Generate and View Reports', 'c', 'Generate and View reports');
insert into system.approle(code, display_value, status, description) values('ArchiveApps', 'Archive applications', 'c', 'Archive applications');
insert into system.approle(code, display_value, status, description) values('ManageSecurity', 'Manage users, groups and roles', 'c', 'Manage users, groups and roles');
insert into system.approle(code, display_value, status, description) values('ManageRefdata', 'Manage reference data', 'c', 'Manage reference data');
insert into system.approle(code, display_value, status, description) values('ManageSettings', 'Manage system settings', 'c', 'Manage system settings');
insert into system.approle(code, display_value, status, description) values('ApplnEdit', 'Application Edit', 'c', 'Allows editing of Applications');
insert into system.approle(code, display_value, status, description) values('ManageBR', 'Manage business rules', 'c', 'Allows to manage business rules');



--Table system.approle_appgroup ----
DROP TABLE IF EXISTS system.approle_appgroup CASCADE;
CREATE TABLE system.approle_appgroup(
    approle_code varchar(20) NOT NULL,
    appgroup_id varchar(40) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT approle_appgroup_pkey PRIMARY KEY (approle_code,appgroup_id)
);


comment on table system.approle_appgroup is 'This many-to-many table contains groups, related to security roles. Allows to have multiple roles for one group.';
    
 -- Data for the table system.approle_appgroup -- 
insert into system.approle_appgroup(approle_code, appgroup_id) values('ManageSecurity', 'admin-group');
insert into system.approle_appgroup(approle_code, appgroup_id) values('ManageRefdata', 'admin-group');
insert into system.approle_appgroup(approle_code, appgroup_id) values('ManageBR', 'admin-group');
insert into system.approle_appgroup(approle_code, appgroup_id) values('ManageSettings', 'admin-group');



--Table system.appgroup ----
DROP TABLE IF EXISTS system.appgroup CASCADE;
CREATE TABLE system.appgroup(
    id varchar(40) NOT NULL,
    name varchar(300) NOT NULL,
    description varchar(500),

    -- Internal constraints
    
    CONSTRAINT appgroup_name_unique UNIQUE (name),
    CONSTRAINT appgroup_pkey PRIMARY KEY (id)
);


comment on table system.appgroup is 'This table contains list of groups, which are used to group users with similar rights in the system.';
    
 -- Data for the table system.appgroup -- 
insert into system.appgroup(id, name, description) values('super-group', 'Super group', 'This is a group of users that has right to use everthing in the application.');
insert into system.appgroup(id, name, description) values('admin-group', 'Admin group', 'This group is used for admin users');



--Table system.appuser_appgroup ----
DROP TABLE IF EXISTS system.appuser_appgroup CASCADE;
CREATE TABLE system.appuser_appgroup(
    appuser_id varchar(40) NOT NULL,
    appgroup_id varchar(40) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT appuser_appgroup_pkey PRIMARY KEY (appuser_id,appgroup_id)
);


comment on table system.appuser_appgroup is 'This many-to-many table contains users, related to groups. Allows to have multiple groups for one user.';
    
 -- Data for the table system.appuser_appgroup -- 
insert into system.appuser_appgroup(appuser_id, appgroup_id) values('admin', 'admin-group');



--Table system.query ----
DROP TABLE IF EXISTS system.query CASCADE;
CREATE TABLE system.query(
    name varchar(100) NOT NULL,
    sql varchar(4000) NOT NULL,
    description varchar(1000),

    -- Internal constraints
    
    CONSTRAINT query_pkey PRIMARY KEY (name)
);


comment on table system.query is 'It defines a query that can be executed by the search ejb.';
    
 -- Data for the table system.query -- 
insert into system.query(name, sql) values('SpatialResult.getParcels', 'select co.id, co.name_lastpart as label,  st_asewkb(co.geom_polygon) as the_geom from cadastre.cadastre_object co where type_code= ''parcel'' and status_code= ''current'' and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))');
insert into system.query(name, sql) values('SpatialResult.getParcelsPending', 'select co.id, co.name_lastpart as label,  st_asewkb(co.geom_polygon) as the_geom  from cadastre.cadastre_object co  where type_code= ''parcel'' and status_code= ''pending''   and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid})) union select co.id, co.name_firstpart || ''/'' || co.name_lastpart as label,  st_asewkb(co_t.geom_polygon) as the_geom  from cadastre.cadastre_object co inner join cadastre.cadastre_object_target co_t on co.id = co_t.cadastre_object_id and co_t.geom_polygon is not null where ST_Intersects(co_t.geom_polygon, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))       and co_t.transaction_id in (select id from transaction.transaction where status_code not in (''approved'')) ');
insert into system.query(name, sql) values('SpatialResult.getApplications', 'select id, nr as label, st_asewkb(location) as the_geom from application.application where ST_Intersects(location, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))');
insert into system.query(name, sql) values('dynamic.informationtool.get_parcel', 'select co.id, co.name_firstpart || ''/'' || co.name_lastpart as parcel_nr,       (select string_agg(ba.name_firstpart || ''/'' || ba.name_lastpart, '','')       from administrative.ba_unit_contains_spatial_unit bas, administrative.ba_unit ba       where spatial_unit_id= co.id and bas.ba_unit_id= ba.id) as ba_units,       ( SELECT spatial_value_area.size FROM cadastre.spatial_value_area       WHERE spatial_value_area.type_code=''officialArea'' and spatial_value_area.spatial_unit_id = co.id) AS area_official_sqm,        ( SELECT spatial_value_area.size * 10.76 FROM cadastre.spatial_value_area       WHERE spatial_value_area.type_code=''officialArea'' and spatial_value_area.spatial_unit_id = co.id) AS area_official_sqf,        st_asewkb(co.geom_polygon) as the_geom      from cadastre.cadastre_object co      where type_code= ''parcel'' and status_code= ''current''      and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_GeomFromWKB(#{wkb_geom}), #{srid}))');
insert into system.query(name, sql) values('dynamic.informationtool.get_parcel_pending', 'select co.id, co.name_firstpart || ''/'' || co.name_lastpart as parcel_nr,       ( SELECT spatial_value_area.size FROM cadastre.spatial_value_area         WHERE spatial_value_area.type_code=''officialArea'' and spatial_value_area.spatial_unit_id = co.id) AS area_official_sqm,   st_asewkb(co.geom_polygon) as the_geom    from cadastre.cadastre_object co  where type_code= ''parcel'' and ((status_code= ''pending''    and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_GeomFromWKB(#{wkb_geom}), #{srid})))   or (co.id in (select cadastre_object_id           from cadastre.cadastre_object_target co_t inner join transaction.transaction t on co_t.transaction_id=t.id           where ST_Intersects(co_t.geom_polygon, ST_SetSRID(ST_GeomFromWKB(#{wkb_geom}), #{srid})) and t.status_code not in (''approved''))))');
insert into system.query(name, sql) values('dynamic.informationtool.get_application', 'select id, nr,  st_asewkb(location) as the_geom from application.application where ST_Intersects(location, ST_SetSRID(ST_GeomFromWKB(#{wkb_geom}), #{srid}))');
insert into system.query(name, sql) values('SpatialResult.getParcelsHistoricWithCurrentBA', 'select co.id, co.name_firstpart || ''/'' || co.name_lastpart as label,  st_asewkb(co.geom_polygon) as the_geom from cadastre.cadastre_object co inner join administrative.ba_unit_contains_spatial_unit ba_co on co.id = ba_co.spatial_unit_id   inner join administrative.ba_unit ba_unit on ba_unit.id= ba_co.ba_unit_id where co.type_code=''parcel'' and co.status_code= ''historic'' and ba_unit.status_code = ''current'' and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))');
insert into system.query(name, sql) values('dynamic.informationtool.get_parcel_historic_current_ba', 'select co.id, co.name_firstpart || ''/'' || co.name_lastpart as parcel_nr,         (select string_agg(ba.name_firstpart || ''/'' || ba.name_lastpart, '','')           from administrative.ba_unit_contains_spatial_unit bas, administrative.ba_unit ba           where spatial_unit_id= co.id and bas.ba_unit_id= ba.id) as ba_units,         (SELECT spatial_value_area.size      FROM cadastre.spatial_value_area           WHERE spatial_value_area.type_code=''officialArea'' and spatial_value_area.spatial_unit_id = co.id) AS area_official_sqm,         st_asewkb(co.geom_polygon) as the_geom        from cadastre.cadastre_object co inner join administrative.ba_unit_contains_spatial_unit ba_co on co.id = ba_co.spatial_unit_id   inner join administrative.ba_unit ba_unit on ba_unit.id= ba_co.ba_unit_id where co.type_code=''parcel'' and co.status_code= ''historic'' and ba_unit.status_code = ''current''       and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_GeomFromWKB(#{wkb_geom}), #{srid}))');
insert into system.query(name, sql) values('map_search.cadastre_object_by_number', 'select id, name_firstpart || ''/ '' || name_lastpart as label, st_asewkb(geom_polygon) as the_geom  from cadastre.cadastre_object  where status_code= ''current'' and compare_strings(#{search_string}, name_firstpart || '' '' || name_lastpart) limit 30');
insert into system.query(name, sql) values('map_search.cadastre_object_by_baunit', 'select distinct co.id,  ba_unit.name_firstpart || ''/ '' || ba_unit.name_lastpart || '' > '' || co.name_firstpart || ''/ '' || co.name_lastpart as label,  st_asewkb(geom_polygon) as the_geom from cadastre.cadastre_object  co    inner join administrative.ba_unit_contains_spatial_unit bas on co.id = bas.spatial_unit_id     inner join administrative.ba_unit on ba_unit.id = bas.ba_unit_id  where (co.status_code= ''current'' or ba_unit.status_code= ''current'')    and compare_strings(#{search_string}, ba_unit.name_firstpart || '' '' || ba_unit.name_lastpart) limit 30');
insert into system.query(name, sql) values('map_search.cadastre_object_by_baunit_owner', 'select distinct co.id,  coalesce(party.name, '''') || '' '' || coalesce(party.last_name, '''') || '' > '' || co.name_firstpart || ''/ '' || co.name_lastpart as label,  st_asewkb(co.geom_polygon) as the_geom from cadastre.cadastre_object  co    inner join administrative.ba_unit_contains_spatial_unit bas on co.id = bas.spatial_unit_id  inner join administrative.ba_unit on bas.ba_unit_id= ba_unit.id   inner join administrative.rrr on (ba_unit.id = rrr.ba_unit_id and rrr.status_code = ''current'' and rrr.type_code = ''ownership'')  inner join administrative.party_for_rrr pfr on rrr.id = pfr.rrr_id   inner join party.party on pfr.party_id= pfr.party_id    where (co.status_code= ''current'' or ba_unit.status_code= ''current'')    and compare_strings(#{search_string}, coalesce(party.name, '''') || '' '' || coalesce(party.last_name, '''')) limit 30');
insert into system.query(name, sql, description) values('system_search.cadastre_object_by_baunit_id', 'SELECT id,  name_firstpart || ''/ '' || name_lastpart as label, st_asewkb(geom_polygon) as the_geom  FROM cadastre.cadastre_object WHERE transaction_id IN (  SELECT cot.transaction_id FROM (administrative.ba_unit_contains_spatial_unit ba_su     INNER JOIN cadastre.cadastre_object co ON ba_su.spatial_unit_id = co.id)     INNER JOIN cadastre.cadastre_object_target cot ON co.id = cot.cadastre_object_id     WHERE ba_su.ba_unit_id = #{search_string})  AND (SELECT COUNT(1) FROM administrative.ba_unit_contains_spatial_unit WHERE spatial_unit_id = cadastre_object.id) = 0 AND status_code = ''current''', 'Query used by BaUnitBean.loadNewParcels');
insert into system.query(name, sql) values('SpatialResult.getRegion', 'select sup.id, sup.code, sup.name, st_asewkb(sup.the_geom) as the_geom from cadastre.region as sup where ST_Intersects(sup.the_geom, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))');
insert into system.query(name, sql) values('SpatialResult.getDistrict', 'select sup.id, sup.num as label, st_asewkb(sup.the_geom) as the_geom from cadastre.district as sup where ST_Intersects(sup.the_geom, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))');
insert into system.query(name, sql) values('SpatialResult.getSection', 'select sup.id, sup.num as label, st_asewkb(sup.the_geom) as the_geom from cadastre.section as sup where ST_Intersects(sup.the_geom, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))');
insert into system.query(name, sql) values('SpatialResult.getBlock', 'select sup.id, sup.num as label, st_asewkb(sup.the_geom) as the_geom from cadastre.block as sup where ST_Intersects(sup.the_geom, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))');
insert into system.query(name, sql) values('dynamic.informationtool.get_region', 'select sup.id, sup.code, sup.name, st_asewkb(sup.the_geom) as the_geom from cadastre.region as sup where ST_Intersects(sup.the_geom, ST_SetSRID(ST_GeomFromWKB(#{wkb_geom}), #{srid}))');
insert into system.query(name, sql) values('dynamic.informationtool.get_district', 'select sup.id, sup.num as label,  st_asewkb(sup.the_geom) as the_geom from cadastre.district as sup where ST_Intersects(sup.the_geom, ST_SetSRID(ST_GeomFromWKB(#{wkb_geom}), #{srid}))');
insert into system.query(name, sql) values('dynamic.informationtool.get_section', 'select sup.id, sup.num as label,  st_asewkb(sup.the_geom) as the_geom from cadastre.section as sup where ST_Intersects(sup.the_geom, ST_SetSRID(ST_GeomFromWKB(#{wkb_geom}), #{srid}))');
insert into system.query(name, sql) values('dynamic.informationtool.get_block', 'select sup.id, sup.num as label,  st_asewkb(sup.the_geom) as the_geom from cadastre.block as sup where ST_Intersects(sup.the_geom, ST_SetSRID(ST_GeomFromWKB(#{wkb_geom}), #{srid}))');
insert into system.query(name, sql) values('map_search.district', 'select id, id as label, st_asewkb(the_geom) as the_geom from cadastre.district where compare_strings(#{search_string}, id) limit 30');
insert into system.query(name, sql) values('map_search.section', 'select id, id || coalesce(''('' || locality || '')'', '''') as label, st_asewkb(the_geom) as the_geom from cadastre.section where compare_strings(#{search_string}, id || coalesce(''('' || locality || '')'', '''')) limit 30');
insert into system.query(name, sql) values('map_search.block', 'select id, id as label, st_asewkb(the_geom) as the_geom from cadastre.block where compare_strings(#{search_string}, id) limit 30');
insert into system.query(name, sql) values('SpatialResult.getBuildings', 'select co.id, co.name_lastpart as label,  st_asewkb(co.geom_polygon) as the_geom from cadastre.cadastre_object co where type_code= ''building'' and status_code= ''current'' and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))');
insert into system.query(name, sql) values('dynamic.informationtool.get_building', 'select co.id, co.name_firstpart || ''/'' || co.name_lastpart as nr, ( SELECT spatial_value_area.size FROM cadastre.spatial_value_area      WHERE spatial_value_area.type_code=''officialArea'' and spatial_value_area.spatial_unit_id = co.id) AS area_official_sqm,       st_asewkb(co.geom_polygon) as the_geom      from cadastre.cadastre_object co      where type_code= ''building'' and status_code= ''current''      and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_GeomFromWKB(#{wkb_geom}), #{srid}))');
insert into system.query(name, sql) values('SpatialResult.getAllodials', 'select co.id, co.name_lastpart as label,  st_asewkb(co.geom_polygon) as the_geom from cadastre.cadastre_object co where type_code= ''allodial'' and status_code= ''current'' and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))');
insert into system.query(name, sql) values('dynamic.informationtool.get_allodial', 'select co.id, co.name_firstpart || ''/'' || co.name_lastpart as nr, ( SELECT spatial_value_area.size FROM cadastre.spatial_value_area      WHERE spatial_value_area.type_code=''officialArea'' and spatial_value_area.spatial_unit_id = co.id) AS area_official_sqm,       st_asewkb(co.geom_polygon) as the_geom      from cadastre.cadastre_object co      where type_code= ''allodial'' and status_code= ''current''      and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_GeomFromWKB(#{wkb_geom}), #{srid}))');
insert into system.query(name, sql) values('SpatialResult.getParcelNodes', 'select distinct st_astext(geom) as id, '''' as label, st_asewkb(geom) as the_geom  from (select (ST_DumpPoints(geom_polygon)).* from cadastre.cadastre_object co   where type_code= ''parcel'' and status_code= ''current''   and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))) tmp_table ');
insert into system.query(name, sql) values('SpatialResult.getParcelPendingCompleted', 'select co.id, co.name_lastpart as label,  st_asewkb(co.geom_polygon) as the_geom from cadastre.cadastre_object co where type_code= ''parcel''    and status_code= ''current''    and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))   and id in (select spatial_unit_id      from application.application_spatial_unit a_su        inner join application.application_status a_s on a_su.application_id = a_s.application_id     where a_s.is_current and a_s.type_code = ''smd-plancertification-completed'')');
insert into system.query(name, sql) values('SpatialResult.getParcelPendingInProgress', 'select co.id, co.name_lastpart as label,  st_asewkb(co.geom_polygon) as the_geom from cadastre.cadastre_object co where type_code= ''parcel''    and status_code= ''current''    and ST_Intersects(co.geom_polygon, ST_SetSRID(ST_MakeBox3D(ST_Point(#{minx}, #{miny}),ST_Point(#{maxx}, #{maxy})), #{srid}))   and id in (select spatial_unit_id      from application.application_spatial_unit a_su      where application.application_is_in_progress(a_su.application_id)) ');



--Table cadastre.cadastre_object_node_target ----
DROP TABLE IF EXISTS cadastre.cadastre_object_node_target CASCADE;
CREATE TABLE cadastre.cadastre_object_node_target(
    transaction_id varchar(40) NOT NULL,
    node_id varchar(40) NOT NULL,
    geom GEOMETRY NOT NULL
        CONSTRAINT enforce_dims_geom CHECK (st_ndims(geom) = 2),
        CONSTRAINT enforce_srid_geom CHECK (st_srid(geom) = 32630),
        CONSTRAINT enforce_valid_geom CHECK (st_isvalid(geom)),
        CONSTRAINT enforce_geotype_geom CHECK (geometrytype(geom) = 'POINT'::text OR geom IS NULL),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT cadastre_object_node_target_pkey PRIMARY KEY (transaction_id,node_id)
);



-- Index cadastre_object_node_target_index_on_geom  --
CREATE INDEX cadastre_object_node_target_index_on_geom ON cadastre.cadastre_object_node_target using gist(geom);
    
-- Index cadastre_object_node_target_index_on_rowidentifier  --
CREATE INDEX cadastre_object_node_target_index_on_rowidentifier ON cadastre.cadastre_object_node_target (rowidentifier);
    

comment on table cadastre.cadastre_object_node_target is 'The nodes that have been changed or added from the transaction.';
    
DROP TRIGGER IF EXISTS __track_changes ON cadastre.cadastre_object_node_target CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON cadastre.cadastre_object_node_target FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table cadastre.cadastre_object_node_target_historic used for the history of data of table cadastre.cadastre_object_node_target ---
DROP TABLE IF EXISTS cadastre.cadastre_object_node_target_historic CASCADE;
CREATE TABLE cadastre.cadastre_object_node_target_historic
(
    transaction_id varchar(40),
    node_id varchar(40),
    geom GEOMETRY
        CONSTRAINT enforce_dims_geom CHECK (st_ndims(geom) = 2),
        CONSTRAINT enforce_srid_geom CHECK (st_srid(geom) = 32630),
        CONSTRAINT enforce_valid_geom CHECK (st_isvalid(geom)),
        CONSTRAINT enforce_geotype_geom CHECK (geometrytype(geom) = 'POINT'::text OR geom IS NULL),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index cadastre_object_node_target_historic_index_on_geom  --
CREATE INDEX cadastre_object_node_target_historic_index_on_geom ON cadastre.cadastre_object_node_target_historic using gist(geom);
    
-- Index cadastre_object_node_target_historic_index_on_rowidentifier  --
CREATE INDEX cadastre_object_node_target_historic_index_on_rowidentifier ON cadastre.cadastre_object_node_target_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON cadastre.cadastre_object_node_target CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON cadastre.cadastre_object_node_target FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table administrative.ba_unit_target ----
DROP TABLE IF EXISTS administrative.ba_unit_target CASCADE;
CREATE TABLE administrative.ba_unit_target(
    ba_unit_id varchar(40) NOT NULL,
    transaction_id varchar(40) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT ba_unit_target_pkey PRIMARY KEY (ba_unit_id,transaction_id)
);



-- Index ba_unit_target_index_on_rowidentifier  --
CREATE INDEX ba_unit_target_index_on_rowidentifier ON administrative.ba_unit_target (rowidentifier);
    

comment on table administrative.ba_unit_target is 'This table holds information about which ba units are being targets of a transaction. It is used when a ba unit is marked for cancellation.';
    
DROP TRIGGER IF EXISTS __track_changes ON administrative.ba_unit_target CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON administrative.ba_unit_target FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table administrative.ba_unit_target_historic used for the history of data of table administrative.ba_unit_target ---
DROP TABLE IF EXISTS administrative.ba_unit_target_historic CASCADE;
CREATE TABLE administrative.ba_unit_target_historic
(
    ba_unit_id varchar(40),
    transaction_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index ba_unit_target_historic_index_on_rowidentifier  --
CREATE INDEX ba_unit_target_historic_index_on_rowidentifier ON administrative.ba_unit_target_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON administrative.ba_unit_target CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON administrative.ba_unit_target FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table system.map_search_option ----
DROP TABLE IF EXISTS system.map_search_option CASCADE;
CREATE TABLE system.map_search_option(
    code varchar(20) NOT NULL,
    title varchar(50) NOT NULL,
    query_name varchar(100) NOT NULL,
    active bool NOT NULL DEFAULT (true),
    min_search_str_len smallint NOT NULL DEFAULT (3),
    zoom_in_buffer numeric(20, 2) NOT NULL DEFAULT (50),
    description varchar(500),

    -- Internal constraints
    
    CONSTRAINT map_search_option_title_unique UNIQUE (title),
    CONSTRAINT map_search_option_pkey PRIMARY KEY (code)
);


comment on table system.map_search_option is 'This table contains information about the options to search objects in the map. The list of options here will be used to configure the list of search by options in the Map Search Component.';
    
 -- Data for the table system.map_search_option -- 
insert into system.map_search_option(code, title, query_name, active, min_search_str_len, zoom_in_buffer) values('NUMBER', 'Parcel by number', 'map_search.cadastre_object_by_number', true, 3, 50);
insert into system.map_search_option(code, title, query_name, active, min_search_str_len, zoom_in_buffer) values('BAUNIT', 'Parcel by property number', 'map_search.cadastre_object_by_baunit', true, 3, 50);
insert into system.map_search_option(code, title, query_name, active, min_search_str_len, zoom_in_buffer) values('OWNER_OF_BAUNIT', 'Parcel by property owner', 'map_search.cadastre_object_by_baunit_owner', true, 3, 50);
insert into system.map_search_option(code, title, query_name, active, min_search_str_len, zoom_in_buffer) values('DISTRICT', 'District', 'map_search.district', true, 2, 50);
insert into system.map_search_option(code, title, query_name, active, min_search_str_len, zoom_in_buffer) values('SECTION', 'Section', 'map_search.section', true, 3, 50);
insert into system.map_search_option(code, title, query_name, active, min_search_str_len, zoom_in_buffer) values('BLOCK', 'Block', 'map_search.block', true, 3, 50);



--Table system.query_field ----
DROP TABLE IF EXISTS system.query_field CASCADE;
CREATE TABLE system.query_field(
    query_name varchar(100) NOT NULL,
    index_in_query integer NOT NULL,
    name varchar(100) NOT NULL,
    display_value varchar(200),

    -- Internal constraints
    
    CONSTRAINT query_field_display_value UNIQUE (query_name, display_value),
    CONSTRAINT query_field_name UNIQUE (query_name, name),
    CONSTRAINT query_field_pkey PRIMARY KEY (query_name,index_in_query)
);


comment on table system.query_field is 'It defines a field in the query. The field is returned by the select part.
Not for all queries is needed to define the fields. It becomes important only for queries that will need to have fields that has to be localized.';
    
 -- Data for the table system.query_field -- 
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_parcel', 1, 'parcel_nr', 'Parcel number::::ITALIANO');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_parcel', 2, 'ba_units', 'Properties::::ITALIANO');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_parcel', 3, 'area_official_sqm', 'Official area (m2)::::ITALIANO');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_parcel', 0, 'id');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_parcel', 5, 'the_geom');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_parcel_pending', 0, 'id');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_parcel_pending', 1, 'parcel_nr', 'Parcel number::::ITALIANO');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_parcel_pending', 2, 'area_official_sqm', 'Official area (m2)::::ITALIANO');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_parcel_pending', 3, 'the_geom');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_application', 0, 'id');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_application', 1, 'nr', 'Number::::Numero');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_application', 2, 'the_geom');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_parcel_historic_current_ba', 0, 'id');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_parcel_historic_current_ba', 1, 'parcel_nr', 'Parcel number::::ITALIANO');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_parcel_historic_current_ba', 2, 'ba_units', 'Properties::::ITALIANO');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_parcel_historic_current_ba', 3, 'area_official_sqm', 'Official area (m2)::::ITALIANO');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_parcel_historic_current_ba', 4, 'the_geom');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_region', 0, 'id');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_region', 1, 'code', 'Code');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_region', 3, 'the_geom');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_district', 0, 'id');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_district', 1, 'label', 'District');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_district', 2, 'the_geom');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_section', 0, 'id');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_section', 1, 'label', 'Section');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_section', 2, 'the_geom');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_block', 0, 'id');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_block', 1, 'label', 'Block');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_block', 2, 'the_geom');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_region', 2, 'name', 'Name');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_building', 0, 'id');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_building', 1, 'nr', 'Number');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_building', 2, 'the_geom');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_allodial', 0, 'id');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_allodial', 1, 'nr', 'Number');
insert into system.query_field(query_name, index_in_query, name) values('dynamic.informationtool.get_allodial', 2, 'the_geom');
insert into system.query_field(query_name, index_in_query, name, display_value) values('dynamic.informationtool.get_parcel', 4, 'area_official_sqf', 'Official area (square feet)');



--Table application.application_party ----
DROP TABLE IF EXISTS application.application_party CASCADE;
CREATE TABLE application.application_party(
    id varchar(40) NOT NULL,
    application_id varchar(40) NOT NULL,
    party_id varchar(40) NOT NULL,
    role_code varchar(20) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT application_party_logical_key UNIQUE (application_id, party_id),
    CONSTRAINT application_party_pkey PRIMARY KEY (id)
);



-- Index application_party_index_on_rowidentifier  --
CREATE INDEX application_party_index_on_rowidentifier ON application.application_party (rowidentifier);
    

comment on table application.application_party is 'Ghana extension: For each application can be a number of parties that can have different roles.
In generic model, there were two parties referenced directly agent_id and contact_person_id. These two parties can be defined through this table so they are removed from the application.';
    
DROP TRIGGER IF EXISTS __track_changes ON application.application_party CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON application.application_party FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table application.application_party_historic used for the history of data of table application.application_party ---
DROP TABLE IF EXISTS application.application_party_historic CASCADE;
CREATE TABLE application.application_party_historic
(
    id varchar(40),
    application_id varchar(40),
    party_id varchar(40),
    role_code varchar(20),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index application_party_historic_index_on_rowidentifier  --
CREATE INDEX application_party_historic_index_on_rowidentifier ON application.application_party_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON application.application_party CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON application.application_party FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table application.fee_type ----
DROP TABLE IF EXISTS application.fee_type CASCADE;
CREATE TABLE application.fee_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT fee_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT fee_type_pkey PRIMARY KEY (code)
);


comment on table application.fee_type is 'Ghana extension: The types of fees applicable for a certain request.';
    
 -- Data for the table application.fee_type -- 
insert into application.fee_type(code, display_value, status) values('planCertificationFee', 'Plan certification fee', 'c');
insert into application.fee_type(code, display_value, status, description) values('regionalNumberFee', 'Regional number fee', 'c', 'Fee that is paid when applying for a regional number');
insert into application.fee_type(code, display_value, status) values('approvalOfPlanFee', 'Approval of plan fee', 'c');
insert into application.fee_type(code, display_value, status) values('reprintOfPlan', 'Reprint of Plan fee', 'c');
insert into application.fee_type(code, display_value, status) values('searchFee', 'Search', 'c');



--Table application.application_fee ----
DROP TABLE IF EXISTS application.application_fee CASCADE;
CREATE TABLE application.application_fee(
    id varchar(40) NOT NULL,
    application_id varchar(40) NOT NULL,
    fee_code varchar(20) NOT NULL,
    paid_amount numeric(20, 2) NOT NULL,
    total_amount numeric(20, 2) NOT NULL,
    receipt_nr varchar(20),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT application_fee_logical_key UNIQUE (application_id, fee_code),
    CONSTRAINT application_fee_amount_check CHECK (paid_amount <= total_amount),
    CONSTRAINT application_fee_pkey PRIMARY KEY (id)
);



-- Index application_fee_index_on_rowidentifier  --
CREATE INDEX application_fee_index_on_rowidentifier ON application.application_fee (rowidentifier);
    

comment on table application.application_fee is 'Ghana extension: The fees that are applicable to an application.
The fees that are listed here are already calculated by other means and they are only recorded.';
    
DROP TRIGGER IF EXISTS __track_changes ON application.application_fee CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON application.application_fee FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table application.application_fee_historic used for the history of data of table application.application_fee ---
DROP TABLE IF EXISTS application.application_fee_historic CASCADE;
CREATE TABLE application.application_fee_historic
(
    id varchar(40),
    application_id varchar(40),
    fee_code varchar(20),
    paid_amount numeric(20, 2),
    total_amount numeric(20, 2),
    receipt_nr varchar(20),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index application_fee_historic_index_on_rowidentifier  --
CREATE INDEX application_fee_historic_index_on_rowidentifier ON application.application_fee_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON application.application_fee CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON application.application_fee FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table application.request_type_fee_type ----
DROP TABLE IF EXISTS application.request_type_fee_type CASCADE;
CREATE TABLE application.request_type_fee_type(
    request_code varchar(50) NOT NULL,
    fee_code varchar(20) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT request_type_fee_type_pkey PRIMARY KEY (request_code,fee_code)
);


comment on table application.request_type_fee_type is 'Ghana extension: The types of fees applicable to a given request type';
    
 -- Data for the table application.request_type_fee_type -- 
insert into application.request_type_fee_type(request_code, fee_code) values('smd-plancertification', 'planCertificationFee');
insert into application.request_type_fee_type(request_code, fee_code) values('smd-plancertification', 'reprintOfPlan');



--Table party.party_id ----
DROP TABLE IF EXISTS party.party_id CASCADE;
CREATE TABLE party.party_id(
    id varchar(40) NOT NULL,
    party_id varchar(40) NOT NULL,
    type_code varchar(20) NOT NULL,
    id_number varchar(20) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT party_id_logical_key UNIQUE (party_id, type_code, id_number),
    CONSTRAINT party_id_pkey PRIMARY KEY (id)
);



-- Index party_id_index_on_rowidentifier  --
CREATE INDEX party_id_index_on_rowidentifier ON party.party_id (rowidentifier);
    

comment on table party.party_id is 'Ghana extension: The list of ids that are associated with a party.
In the generic model, there was space only for one id defined by the columns id_type_code and id_number. These columns are removed from the party.';
    
DROP TRIGGER IF EXISTS __track_changes ON party.party_id CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON party.party_id FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table party.party_id_historic used for the history of data of table party.party_id ---
DROP TABLE IF EXISTS party.party_id_historic CASCADE;
CREATE TABLE party.party_id_historic
(
    id varchar(40),
    party_id varchar(40),
    type_code varchar(20),
    id_number varchar(20),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index party_id_historic_index_on_rowidentifier  --
CREATE INDEX party_id_historic_index_on_rowidentifier ON party.party_id_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON party.party_id CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON party.party_id FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table application.application_action ----
DROP TABLE IF EXISTS application.application_action CASCADE;
CREATE TABLE application.application_action(
    id varchar(40) NOT NULL,
    status_id varchar(40) NOT NULL,
    type_code varchar(50) NOT NULL,
    is_done bool NOT NULL DEFAULT (false),
    remarks varchar(500),
    action_order integer NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT application_action_action UNIQUE (status_id, type_code),
    CONSTRAINT application_action_pkey PRIMARY KEY (id)
);



-- Index application_action_index_on_rowidentifier  --
CREATE INDEX application_action_index_on_rowidentifier ON application.application_action (rowidentifier);
    

comment on table application.application_action is 'The list of actions belonging to a certain status. In the moment that the application goes to a new status, the list of actions for this status is filled in.';
    
DROP TRIGGER IF EXISTS __track_changes ON application.application_action CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON application.application_action FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table application.application_action_historic used for the history of data of table application.application_action ---
DROP TABLE IF EXISTS application.application_action_historic CASCADE;
CREATE TABLE application.application_action_historic
(
    id varchar(40),
    status_id varchar(40),
    type_code varchar(50),
    is_done bool,
    remarks varchar(500),
    action_order integer,
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index application_action_historic_index_on_rowidentifier  --
CREATE INDEX application_action_historic_index_on_rowidentifier ON application.application_action_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON application.application_action CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON application.application_action FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table application.application_status ----
DROP TABLE IF EXISTS application.application_status CASCADE;
CREATE TABLE application.application_status(
    id varchar(40) NOT NULL,
    application_id varchar(40) NOT NULL,
    type_code varchar(50) NOT NULL,
    is_current bool NOT NULL DEFAULT (true),
    date_enter timestamp NOT NULL DEFAULT (now()),
    date_leave timestamp,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT application_status_pkey PRIMARY KEY (id)
);



-- Index application_status_index_on_rowidentifier  --
CREATE INDEX application_status_index_on_rowidentifier ON application.application_status (rowidentifier);
    

comment on table application.application_status is 'The statuses that an application went through. The first status of the application is defined in the moment when the application is created. The status type is defined in the field of request_type.start_status_code.';
    
DROP TRIGGER IF EXISTS __track_changes ON application.application_status CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON application.application_status FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table application.application_status_historic used for the history of data of table application.application_status ---
DROP TABLE IF EXISTS application.application_status_historic CASCADE;
CREATE TABLE application.application_status_historic
(
    id varchar(40),
    application_id varchar(40),
    type_code varchar(50),
    is_current bool,
    date_enter timestamp,
    date_leave timestamp,
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index application_status_historic_index_on_rowidentifier  --
CREATE INDEX application_status_historic_index_on_rowidentifier ON application.application_status_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON application.application_status CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON application.application_status FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table application.operation_type ----
DROP TABLE IF EXISTS application.operation_type CASCADE;
CREATE TABLE application.operation_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    description varchar(555),
    status char(1) NOT NULL DEFAULT ('t'),

    -- Internal constraints
    
    CONSTRAINT operation_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT operation_type_pkey PRIMARY KEY (code)
);


comment on table application.operation_type is 'The list of operations that can happen to an application when an action is marked as done.';
    
 -- Data for the table application.operation_type -- 
insert into application.operation_type(code, display_value, description, status) values('normal', 'Normal', 'Nothing changes to the application.', 'c');
insert into application.operation_type(code, display_value, description, status) values('validate', 'Validate', 'The application is validated. If the validation fails the action is not completed.', 'c');
insert into application.operation_type(code, display_value, description, status) values('cancel', 'Cancel', 'The application is cancelled.', 'c');
insert into application.operation_type(code, display_value, description, status) values('approve', 'Approve', 'The application is approved. Before the approval, the application is validated. If the validation succeeds then the process goes further with the approval.', 'c');
insert into application.operation_type(code, display_value, description, status) values('change', 'Change', 'The application changes', 'c');



--Table application.application_spatial_unit ----
DROP TABLE IF EXISTS application.application_spatial_unit CASCADE;
CREATE TABLE application.application_spatial_unit(
    application_id varchar(40) NOT NULL,
    spatial_unit_id varchar(40) NOT NULL,
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT application_spatial_unit_pkey PRIMARY KEY (application_id,spatial_unit_id)
);



-- Index application_spatial_unit_index_on_rowidentifier  --
CREATE INDEX application_spatial_unit_index_on_rowidentifier ON application.application_spatial_unit (rowidentifier);
    

comment on table application.application_spatial_unit is '';
    
DROP TRIGGER IF EXISTS __track_changes ON application.application_spatial_unit CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON application.application_spatial_unit FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table application.application_spatial_unit_historic used for the history of data of table application.application_spatial_unit ---
DROP TABLE IF EXISTS application.application_spatial_unit_historic CASCADE;
CREATE TABLE application.application_spatial_unit_historic
(
    application_id varchar(40),
    spatial_unit_id varchar(40),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index application_spatial_unit_historic_index_on_rowidentifier  --
CREATE INDEX application_spatial_unit_historic_index_on_rowidentifier ON application.application_spatial_unit_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON application.application_spatial_unit CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON application.application_spatial_unit FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
--Table source.deed ----
DROP TABLE IF EXISTS source.deed CASCADE;
CREATE TABLE source.deed(
    id varchar(40) NOT NULL,
    no varchar(30) NOT NULL,
    instrument_type_code varchar(20) NOT NULL,
    first_party_id varchar(40) NOT NULL,
    second_party_id varchar(40) NOT NULL,
    forward_reference_id varchar(40),
    backward_reference_id varchar(40),
    file_no varchar(50),
    property_nr varchar(30),
    land_use_code varchar(20),

    -- Internal constraints
    
    CONSTRAINT deed_pkey PRIMARY KEY (id)
);


comment on table source.deed is '';
    
--Table cadastre.region ----
DROP TABLE IF EXISTS cadastre.region CASCADE;
CREATE TABLE cadastre.region(
    id varchar(40) NOT NULL,
    code varchar(5) NOT NULL,
    name varchar(30) NOT NULL,
    the_geom GEOMETRY
        CONSTRAINT enforce_dims_the_geom CHECK (st_ndims(the_geom) = 2),
        CONSTRAINT enforce_srid_the_geom CHECK (st_srid(the_geom) = 32630),
        CONSTRAINT enforce_valid_the_geom CHECK (st_isvalid(the_geom)),
        CONSTRAINT enforce_geotype_the_geom CHECK (geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL),
    app_regnr_counter varchar(5),
    app_regnr_counter_year varchar(4),

    -- Internal constraints
    
    CONSTRAINT region_code_unique UNIQUE (code),
    CONSTRAINT region_pkey PRIMARY KEY (id)
);



-- Index region_index_on_the_geom  --
CREATE INDEX region_index_on_the_geom ON cadastre.region using gist(the_geom);
    

comment on table cadastre.region is '';
    
--Table cadastre.district ----
DROP TABLE IF EXISTS cadastre.district CASCADE;
CREATE TABLE cadastre.district(
    id varchar(40) NOT NULL,
    region_id varchar(40) NOT NULL,
    num varchar(30) NOT NULL,
    year_declared integer NOT NULL,
    the_geom GEOMETRY
        CONSTRAINT enforce_dims_the_geom CHECK (st_ndims(the_geom) = 2),
        CONSTRAINT enforce_srid_the_geom CHECK (st_srid(the_geom) = 32630),
        CONSTRAINT enforce_valid_the_geom CHECK (st_isvalid(the_geom)),
        CONSTRAINT enforce_geotype_the_geom CHECK (geometrytype(the_geom) = 'POLYGON'::text OR the_geom IS NULL),

    -- Internal constraints
    
    CONSTRAINT district_pkey PRIMARY KEY (id)
);



-- Index district_index_on_the_geom  --
CREATE INDEX district_index_on_the_geom ON cadastre.district using gist(the_geom);
    

comment on table cadastre.district is '';
    
--Table cadastre.section ----
DROP TABLE IF EXISTS cadastre.section CASCADE;
CREATE TABLE cadastre.section(
    id varchar(40) NOT NULL,
    district_id varchar(40) NOT NULL,
    num varchar(30) NOT NULL,
    locality varchar(200),
    the_geom GEOMETRY
        CONSTRAINT enforce_dims_the_geom CHECK (st_ndims(the_geom) = 2),
        CONSTRAINT enforce_srid_the_geom CHECK (st_srid(the_geom) = 32630),
        CONSTRAINT enforce_valid_the_geom CHECK (st_isvalid(the_geom)),
        CONSTRAINT enforce_geotype_the_geom CHECK (geometrytype(the_geom) = 'POLYGON'::text OR the_geom IS NULL),

    -- Internal constraints
    
    CONSTRAINT section_pkey PRIMARY KEY (id)
);



-- Index section_index_on_the_geom  --
CREATE INDEX section_index_on_the_geom ON cadastre.section using gist(the_geom);
    

comment on table cadastre.section is '';
    
--Table cadastre.block ----
DROP TABLE IF EXISTS cadastre.block CASCADE;
CREATE TABLE cadastre.block(
    id varchar(40) NOT NULL,
    section_id varchar(40) NOT NULL,
    num varchar(30) NOT NULL,
    is_pseudo bool NOT NULL DEFAULT (false),
    the_geom GEOMETRY
        CONSTRAINT enforce_dims_the_geom CHECK (st_ndims(the_geom) = 2),
        CONSTRAINT enforce_srid_the_geom CHECK (st_srid(the_geom) = 32630),
        CONSTRAINT enforce_valid_the_geom CHECK (st_isvalid(the_geom)),
        CONSTRAINT enforce_geotype_the_geom CHECK (geometrytype(the_geom) = 'POLYGON'::text OR the_geom IS NULL),

    -- Internal constraints
    
    CONSTRAINT block_pkey PRIMARY KEY (id)
);



-- Index block_index_on_the_geom  --
CREATE INDEX block_index_on_the_geom ON cadastre.block using gist(the_geom);
    

comment on table cadastre.block is '';
    
--Table source.land_use_type ----
DROP TABLE IF EXISTS source.land_use_type CASCADE;
CREATE TABLE source.land_use_type(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT land_use_type_display_value_unique UNIQUE (display_value),
    CONSTRAINT land_use_type_pkey PRIMARY KEY (code)
);


comment on table source.land_use_type is 'Ghana extension: It contains the list of possible land use types.';
    
 -- Data for the table source.land_use_type -- 
insert into source.land_use_type(code, display_value, status) values('residential', 'Residential', 'c');
insert into source.land_use_type(code, display_value, status) values('commercial', 'Commercial', 'c');
insert into source.land_use_type(code, display_value, status) values('industrial', 'Industrial', 'c');
insert into source.land_use_type(code, display_value, status) values('educational', 'Educational', 'c');
insert into source.land_use_type(code, display_value, status) values('agricultural', 'Agricultural', 'c');
insert into source.land_use_type(code, display_value, status) values('recreational', 'Recreational', 'c');
insert into source.land_use_type(code, display_value, status) values('civic-cultural', 'Civic & Cultural', 'c');



--Table party.country ----
DROP TABLE IF EXISTS party.country CASCADE;
CREATE TABLE party.country(
    code varchar(20) NOT NULL,
    display_value varchar(250) NOT NULL,
    status char(1) NOT NULL DEFAULT ('t'),
    description varchar(555),

    -- Internal constraints
    
    CONSTRAINT country_display_value_unique UNIQUE (display_value),
    CONSTRAINT country_pkey PRIMARY KEY (code)
);


comment on table party.country is 'Ghana extension: List of countries that are used in the system.';
    
 -- Data for the table party.country -- 
insert into party.country(code, display_value, status) values('GH', 'Ghana', 'c');
insert into party.country(code, display_value, status) values('NG', 'Nigeria', 'c');



--Table source.power_of_attorney ----
DROP TABLE IF EXISTS source.power_of_attorney CASCADE;
CREATE TABLE source.power_of_attorney(
    id varchar(40) NOT NULL,
    person_name varchar(500) NOT NULL,
    attorney_name varchar(500) NOT NULL,

    -- Internal constraints
    
    CONSTRAINT power_of_attorney_pkey PRIMARY KEY (id)
);


comment on table source.power_of_attorney is '';
    
--Table system.office ----
DROP TABLE IF EXISTS system.office CASCADE;
CREATE TABLE system.office(
    code varchar(40) NOT NULL,
    display_value varchar(100) NOT NULL,
    status char(1) NOT NULL,
    description varchar(555),
    rowidentifier varchar(40) NOT NULL DEFAULT (uuid_generate_v1()),
    rowversion integer NOT NULL DEFAULT (0),
    change_action char(1) NOT NULL DEFAULT ('i'),
    change_user varchar(50),
    change_time timestamp NOT NULL DEFAULT (now()),

    -- Internal constraints
    
    CONSTRAINT office_display_value_unique UNIQUE (display_value),
    CONSTRAINT office_pkey PRIMARY KEY (code)
);



-- Index office_index_on_rowidentifier  --
CREATE INDEX office_index_on_rowidentifier ON system.office (rowidentifier);
    

comment on table system.office is 'Ghana extension: The office that is involved in the system. Every office can have one or more users. One of those users has to be the head of the office.';
    
DROP TRIGGER IF EXISTS __track_changes ON system.office CASCADE;
CREATE TRIGGER __track_changes BEFORE UPDATE OR INSERT
   ON system.office FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_changes();
    

----Table system.office_historic used for the history of data of table system.office ---
DROP TABLE IF EXISTS system.office_historic CASCADE;
CREATE TABLE system.office_historic
(
    code varchar(40),
    display_value varchar(100),
    status char(1),
    description varchar(555),
    rowidentifier varchar(40),
    rowversion integer,
    change_action char(1),
    change_user varchar(50),
    change_time timestamp,
    change_time_valid_until TIMESTAMP NOT NULL default NOW()
);


-- Index office_historic_index_on_rowidentifier  --
CREATE INDEX office_historic_index_on_rowidentifier ON system.office_historic (rowidentifier);
    

DROP TRIGGER IF EXISTS __track_history ON system.office CASCADE;
CREATE TRIGGER __track_history AFTER UPDATE OR DELETE
   ON system.office FOR EACH ROW
   EXECUTE PROCEDURE f_for_trg_track_history();
    
 -- Data for the table system.office -- 
insert into system.office(code, display_value, status) values('csau', 'CSAU', 'c');
insert into system.office(code, display_value, status) values('smd-registry', 'SMD Registry', 'c');
insert into system.office(code, display_value, status) values('cartographic-gis-section', 'Cartographic and GIS Section', 'c');
insert into system.office(code, display_value, status) values('archive', 'Archive', 'c');
insert into system.office(code, display_value, status) values('it', 'IT', 'c');




ALTER TABLE source.spatial_source ADD CONSTRAINT spatial_source_type_code_fk0 
            FOREIGN KEY (type_code) REFERENCES source.spatial_source_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX spatial_source_type_code_fk0_ind ON source.spatial_source (type_code);

ALTER TABLE source.spatial_source_measurement ADD CONSTRAINT spatial_source_measurement_spatial_source_id_fk1 
            FOREIGN KEY (spatial_source_id) REFERENCES source.spatial_source(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX spatial_source_measurement_spatial_source_id_fk1_ind ON source.spatial_source_measurement (spatial_source_id);

ALTER TABLE party.party ADD CONSTRAINT party_type_code_fk2 
            FOREIGN KEY (type_code) REFERENCES party.party_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX party_type_code_fk2_ind ON party.party (type_code);

ALTER TABLE party.group_party ADD CONSTRAINT group_party_type_code_fk3 
            FOREIGN KEY (type_code) REFERENCES party.group_party_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX group_party_type_code_fk3_ind ON party.group_party (type_code);

ALTER TABLE party.party_member ADD CONSTRAINT party_member_party_id_fk4 
            FOREIGN KEY (party_id) REFERENCES party.party(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX party_member_party_id_fk4_ind ON party.party_member (party_id);

ALTER TABLE party.party_member ADD CONSTRAINT party_member_group_id_fk5 
            FOREIGN KEY (group_id) REFERENCES party.group_party(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX party_member_group_id_fk5_ind ON party.party_member (group_id);

ALTER TABLE administrative.ba_unit ADD CONSTRAINT ba_unit_type_code_fk6 
            FOREIGN KEY (type_code) REFERENCES administrative.ba_unit_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX ba_unit_type_code_fk6_ind ON administrative.ba_unit (type_code);

ALTER TABLE administrative.rrr ADD CONSTRAINT rrr_ba_unit_id_fk7 
            FOREIGN KEY (ba_unit_id) REFERENCES administrative.ba_unit(id) ON UPDATE CASCADE ON DELETE Cascade;
CREATE INDEX rrr_ba_unit_id_fk7_ind ON administrative.rrr (ba_unit_id);

ALTER TABLE administrative.rrr_type ADD CONSTRAINT rrr_type_rrr_group_type_code_fk8 
            FOREIGN KEY (rrr_group_type_code) REFERENCES administrative.rrr_group_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX rrr_type_rrr_group_type_code_fk8_ind ON administrative.rrr_type (rrr_group_type_code);

ALTER TABLE administrative.rrr ADD CONSTRAINT rrr_type_code_fk9 
            FOREIGN KEY (type_code) REFERENCES administrative.rrr_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX rrr_type_code_fk9_ind ON administrative.rrr (type_code);

ALTER TABLE party.group_party ADD CONSTRAINT group_party_id_fk10 
            FOREIGN KEY (id) REFERENCES party.party(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX group_party_id_fk10_ind ON party.group_party (id);

ALTER TABLE source.spatial_source ADD CONSTRAINT spatial_source_id_fk11 
            FOREIGN KEY (id) REFERENCES source.source(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX spatial_source_id_fk11_ind ON source.spatial_source (id);

ALTER TABLE administrative.source_describes_rrr ADD CONSTRAINT source_describes_rrr_rrr_id_fk12 
            FOREIGN KEY (rrr_id) REFERENCES administrative.rrr(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX source_describes_rrr_rrr_id_fk12_ind ON administrative.source_describes_rrr (rrr_id);

ALTER TABLE administrative.source_describes_ba_unit ADD CONSTRAINT source_describes_ba_unit_ba_unit_id_fk13 
            FOREIGN KEY (ba_unit_id) REFERENCES administrative.ba_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX source_describes_ba_unit_ba_unit_id_fk13_ind ON administrative.source_describes_ba_unit (ba_unit_id);

ALTER TABLE administrative.required_relationship_baunit ADD CONSTRAINT required_relationship_baunit_from_ba_unit_id_fk14 
            FOREIGN KEY (from_ba_unit_id) REFERENCES administrative.ba_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX required_relationship_baunit_from_ba_unit_id_fk14_ind ON administrative.required_relationship_baunit (from_ba_unit_id);

ALTER TABLE administrative.required_relationship_baunit ADD CONSTRAINT required_relationship_baunit_to_ba_unit_id_fk15 
            FOREIGN KEY (to_ba_unit_id) REFERENCES administrative.ba_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX required_relationship_baunit_to_ba_unit_id_fk15_ind ON administrative.required_relationship_baunit (to_ba_unit_id);

ALTER TABLE cadastre.spatial_value_area ADD CONSTRAINT spatial_value_area_spatial_unit_id_fk16 
            FOREIGN KEY (spatial_unit_id) REFERENCES cadastre.spatial_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX spatial_value_area_spatial_unit_id_fk16_ind ON cadastre.spatial_value_area (spatial_unit_id);

ALTER TABLE cadastre.spatial_value_area ADD CONSTRAINT spatial_value_area_type_code_fk17 
            FOREIGN KEY (type_code) REFERENCES cadastre.area_type(code) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX spatial_value_area_type_code_fk17_ind ON cadastre.spatial_value_area (type_code);

ALTER TABLE cadastre.spatial_unit_address ADD CONSTRAINT spatial_unit_address_spatial_unit_id_fk18 
            FOREIGN KEY (spatial_unit_id) REFERENCES cadastre.spatial_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX spatial_unit_address_spatial_unit_id_fk18_ind ON cadastre.spatial_unit_address (spatial_unit_id);

ALTER TABLE cadastre.spatial_unit ADD CONSTRAINT spatial_unit_surface_relation_code_fk19 
            FOREIGN KEY (surface_relation_code) REFERENCES cadastre.surface_relation_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX spatial_unit_surface_relation_code_fk19_ind ON cadastre.spatial_unit (surface_relation_code);

ALTER TABLE cadastre.spatial_unit ADD CONSTRAINT spatial_unit_level_id_fk20 
            FOREIGN KEY (level_id) REFERENCES cadastre.level(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX spatial_unit_level_id_fk20_ind ON cadastre.spatial_unit (level_id);

ALTER TABLE cadastre.level ADD CONSTRAINT level_structure_code_fk21 
            FOREIGN KEY (structure_code) REFERENCES cadastre.structure_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX level_structure_code_fk21_ind ON cadastre.level (structure_code);

ALTER TABLE cadastre.level ADD CONSTRAINT level_register_type_code_fk22 
            FOREIGN KEY (register_type_code) REFERENCES cadastre.register_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX level_register_type_code_fk22_ind ON cadastre.level (register_type_code);

ALTER TABLE cadastre.level ADD CONSTRAINT level_type_code_fk23 
            FOREIGN KEY (type_code) REFERENCES cadastre.level_content_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX level_type_code_fk23_ind ON cadastre.level (type_code);

ALTER TABLE administrative.ba_unit_contains_spatial_unit ADD CONSTRAINT ba_unit_contains_spatial_unit_ba_unit_id_fk24 
            FOREIGN KEY (ba_unit_id) REFERENCES administrative.ba_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX ba_unit_contains_spatial_unit_ba_unit_id_fk24_ind ON administrative.ba_unit_contains_spatial_unit (ba_unit_id);

ALTER TABLE administrative.ba_unit_contains_spatial_unit ADD CONSTRAINT ba_unit_contains_spatial_unit_spatial_unit_id_fk25 
            FOREIGN KEY (spatial_unit_id) REFERENCES cadastre.spatial_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX ba_unit_contains_spatial_unit_spatial_unit_id_fk25_ind ON administrative.ba_unit_contains_spatial_unit (spatial_unit_id);

ALTER TABLE cadastre.legal_space_utility_network ADD CONSTRAINT legal_space_utility_network_status_code_fk26 
            FOREIGN KEY (status_code) REFERENCES cadastre.utility_network_status_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX legal_space_utility_network_status_code_fk26_ind ON cadastre.legal_space_utility_network (status_code);

ALTER TABLE cadastre.legal_space_utility_network ADD CONSTRAINT legal_space_utility_network_type_code_fk27 
            FOREIGN KEY (type_code) REFERENCES cadastre.utility_network_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX legal_space_utility_network_type_code_fk27_ind ON cadastre.legal_space_utility_network (type_code);

ALTER TABLE application.request_type ADD CONSTRAINT request_type_request_category_code_fk28 
            FOREIGN KEY (request_category_code) REFERENCES application.request_category_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX request_type_request_category_code_fk28_ind ON application.request_type (request_category_code);

ALTER TABLE party.party_role ADD CONSTRAINT party_role_type_code_fk29 
            FOREIGN KEY (type_code) REFERENCES party.party_role_type(code) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX party_role_type_code_fk29_ind ON party.party_role (type_code);

ALTER TABLE party.party_role ADD CONSTRAINT party_role_party_id_fk30 
            FOREIGN KEY (party_id) REFERENCES party.party(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX party_role_party_id_fk30_ind ON party.party_role (party_id);

ALTER TABLE party.party ADD CONSTRAINT party_physical_address_id_fk31 
            FOREIGN KEY (physical_address_id) REFERENCES address.address(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX party_physical_address_id_fk31_ind ON party.party (physical_address_id);

ALTER TABLE cadastre.spatial_unit_address ADD CONSTRAINT spatial_unit_address_address_id_fk32 
            FOREIGN KEY (address_id) REFERENCES address.address(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX spatial_unit_address_address_id_fk32_ind ON cadastre.spatial_unit_address (address_id);

ALTER TABLE cadastre.spatial_unit ADD CONSTRAINT spatial_unit_dimension_code_fk33 
            FOREIGN KEY (dimension_code) REFERENCES cadastre.dimension_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX spatial_unit_dimension_code_fk33_ind ON cadastre.spatial_unit (dimension_code);

ALTER TABLE party.party ADD CONSTRAINT party_preferred_communication_code_fk34 
            FOREIGN KEY (preferred_communication_code) REFERENCES party.communication_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX party_preferred_communication_code_fk34_ind ON party.party (preferred_communication_code);

ALTER TABLE source.source ADD CONSTRAINT source_maintype_fk35 
            FOREIGN KEY (maintype) REFERENCES source.presentation_form_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX source_maintype_fk35_ind ON source.source (maintype);

ALTER TABLE source.source ADD CONSTRAINT source_archive_id_fk36 
            FOREIGN KEY (archive_id) REFERENCES source.archive(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX source_archive_id_fk36_ind ON source.source (archive_id);

ALTER TABLE application.application_property ADD CONSTRAINT application_property_application_id_fk37 
            FOREIGN KEY (application_id) REFERENCES application.application(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX application_property_application_id_fk37_ind ON application.application_property (application_id);

ALTER TABLE application.application_uses_source ADD CONSTRAINT application_uses_source_source_id_fk38 
            FOREIGN KEY (source_id) REFERENCES source.source(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_uses_source_source_id_fk38_ind ON application.application_uses_source (source_id);

ALTER TABLE application.application_uses_source ADD CONSTRAINT application_uses_source_application_id_fk39 
            FOREIGN KEY (application_id) REFERENCES application.application(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_uses_source_application_id_fk39_ind ON application.application_uses_source (application_id);

ALTER TABLE application.request_type_requires_source_type ADD CONSTRAINT request_type_requires_source_type_request_type_code_fk40 
            FOREIGN KEY (request_type_code) REFERENCES application.request_type(code) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX request_type_requires_source_type_request_type_code_fk40_ind ON application.request_type_requires_source_type (request_type_code);

ALTER TABLE application.application_property ADD CONSTRAINT application_property_ba_unit_id_fk41 
            FOREIGN KEY (ba_unit_id) REFERENCES administrative.ba_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX application_property_ba_unit_id_fk41_ind ON application.application_property (ba_unit_id);

ALTER TABLE application.application ADD CONSTRAINT application_assignee_id_fk42 
            FOREIGN KEY (assignee_id) REFERENCES system.appuser(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_assignee_id_fk42_ind ON application.application (assignee_id);

ALTER TABLE system.appuser_setting ADD CONSTRAINT appuser_setting_user_id_fk43 
            FOREIGN KEY (user_id) REFERENCES system.appuser(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX appuser_setting_user_id_fk43_ind ON system.appuser_setting (user_id);

ALTER TABLE source.source ADD CONSTRAINT source_availability_status_code_fk44 
            FOREIGN KEY (availability_status_code) REFERENCES source.availability_status_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX source_availability_status_code_fk44_ind ON source.source (availability_status_code);

ALTER TABLE source.source ADD CONSTRAINT source_type_code_fk45 
            FOREIGN KEY (type_code) REFERENCES source.administrative_source_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX source_type_code_fk45_ind ON source.source (type_code);

ALTER TABLE application.request_type_requires_source_type ADD CONSTRAINT request_type_requires_source_type_source_type_code_fk46 
            FOREIGN KEY (source_type_code) REFERENCES source.administrative_source_type(code) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX request_type_requires_source_type_source_type_code_fk46_ind ON application.request_type_requires_source_type (source_type_code);

ALTER TABLE system.config_map_layer ADD CONSTRAINT config_map_layer_type_code_fk47 
            FOREIGN KEY (type_code) REFERENCES system.config_map_layer_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX config_map_layer_type_code_fk47_ind ON system.config_map_layer (type_code);

ALTER TABLE administrative.ba_unit_as_party ADD CONSTRAINT ba_unit_as_party_party_id_fk48 
            FOREIGN KEY (party_id) REFERENCES party.party(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX ba_unit_as_party_party_id_fk48_ind ON administrative.ba_unit_as_party (party_id);

ALTER TABLE administrative.ba_unit_as_party ADD CONSTRAINT ba_unit_as_party_ba_unit_id_fk49 
            FOREIGN KEY (ba_unit_id) REFERENCES administrative.ba_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX ba_unit_as_party_ba_unit_id_fk49_ind ON administrative.ba_unit_as_party (ba_unit_id);

ALTER TABLE system.br ADD CONSTRAINT br_technical_type_code_fk50 
            FOREIGN KEY (technical_type_code) REFERENCES system.br_technical_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX br_technical_type_code_fk50_ind ON system.br (technical_type_code);

ALTER TABLE system.br_validation ADD CONSTRAINT br_validation_br_id_fk51 
            FOREIGN KEY (br_id) REFERENCES system.br(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX br_validation_br_id_fk51_ind ON system.br_validation (br_id);

ALTER TABLE system.br_definition ADD CONSTRAINT br_definition_br_id_fk52 
            FOREIGN KEY (br_id) REFERENCES system.br(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX br_definition_br_id_fk52_ind ON system.br_definition (br_id);

ALTER TABLE system.br_validation ADD CONSTRAINT br_validation_severity_code_fk53 
            FOREIGN KEY (severity_code) REFERENCES system.br_severity_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX br_validation_severity_code_fk53_ind ON system.br_validation (severity_code);

ALTER TABLE system.br_validation ADD CONSTRAINT br_validation_target_code_fk54 
            FOREIGN KEY (target_code) REFERENCES system.br_validation_target_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX br_validation_target_code_fk54_ind ON system.br_validation (target_code);

ALTER TABLE system.br_validation ADD CONSTRAINT br_validation_target_request_type_code_fk55 
            FOREIGN KEY (target_request_type_code) REFERENCES application.request_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX br_validation_target_request_type_code_fk55_ind ON system.br_validation (target_request_type_code);

ALTER TABLE system.br_validation ADD CONSTRAINT br_validation_target_rrr_type_code_fk56 
            FOREIGN KEY (target_rrr_type_code) REFERENCES administrative.rrr_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX br_validation_target_rrr_type_code_fk56_ind ON system.br_validation (target_rrr_type_code);

ALTER TABLE administrative.mortgage_isbased_in_rrr ADD CONSTRAINT mortgage_isbased_in_rrr_rrr_id_fk57 
            FOREIGN KEY (rrr_id) REFERENCES administrative.rrr(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX mortgage_isbased_in_rrr_rrr_id_fk57_ind ON administrative.mortgage_isbased_in_rrr (rrr_id);

ALTER TABLE administrative.mortgage_isbased_in_rrr ADD CONSTRAINT mortgage_isbased_in_rrr_mortgage_id_fk58 
            FOREIGN KEY (mortgage_id) REFERENCES administrative.rrr(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX mortgage_isbased_in_rrr_mortgage_id_fk58_ind ON administrative.mortgage_isbased_in_rrr (mortgage_id);

ALTER TABLE administrative.rrr ADD CONSTRAINT rrr_status_code_fk59 
            FOREIGN KEY (status_code) REFERENCES transaction.reg_status_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX rrr_status_code_fk59_ind ON administrative.rrr (status_code);

ALTER TABLE administrative.ba_unit ADD CONSTRAINT ba_unit_status_code_fk60 
            FOREIGN KEY (status_code) REFERENCES transaction.reg_status_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX ba_unit_status_code_fk60_ind ON administrative.ba_unit (status_code);

ALTER TABLE cadastre.cadastre_object ADD CONSTRAINT cadastre_object_id_fk61 
            FOREIGN KEY (id) REFERENCES cadastre.spatial_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX cadastre_object_id_fk61_ind ON cadastre.cadastre_object (id);

ALTER TABLE cadastre.cadastre_object ADD CONSTRAINT cadastre_object_status_code_fk62 
            FOREIGN KEY (status_code) REFERENCES transaction.reg_status_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX cadastre_object_status_code_fk62_ind ON cadastre.cadastre_object (status_code);

ALTER TABLE cadastre.cadastre_object ADD CONSTRAINT cadastre_object_type_code_fk63 
            FOREIGN KEY (type_code) REFERENCES cadastre.cadastre_object_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX cadastre_object_type_code_fk63_ind ON cadastre.cadastre_object (type_code);

ALTER TABLE cadastre.legal_space_utility_network ADD CONSTRAINT legal_space_utility_network_id_fk64 
            FOREIGN KEY (id) REFERENCES cadastre.cadastre_object(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX legal_space_utility_network_id_fk64_ind ON cadastre.legal_space_utility_network (id);

ALTER TABLE administrative.source_describes_ba_unit ADD CONSTRAINT source_describes_ba_unit_source_id_fk65 
            FOREIGN KEY (source_id) REFERENCES source.source(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX source_describes_ba_unit_source_id_fk65_ind ON administrative.source_describes_ba_unit (source_id);

ALTER TABLE administrative.required_relationship_baunit ADD CONSTRAINT required_relationship_baunit_relation_code_fk66 
            FOREIGN KEY (relation_code) REFERENCES administrative.ba_unit_rel_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX required_relationship_baunit_relation_code_fk66_ind ON administrative.required_relationship_baunit (relation_code);

ALTER TABLE administrative.ba_unit_contains_spatial_unit ADD CONSTRAINT ba_unit_contains_spatial_unit_spatial_unit_id_fk67 
            FOREIGN KEY (spatial_unit_id) REFERENCES cadastre.cadastre_object(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX ba_unit_contains_spatial_unit_spatial_unit_id_fk67_ind ON administrative.ba_unit_contains_spatial_unit (spatial_unit_id);

ALTER TABLE administrative.notation ADD CONSTRAINT notation_status_code_fk68 
            FOREIGN KEY (status_code) REFERENCES transaction.reg_status_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX notation_status_code_fk68_ind ON administrative.notation (status_code);

ALTER TABLE administrative.notation ADD CONSTRAINT notation_ba_unit_id_fk69 
            FOREIGN KEY (ba_unit_id) REFERENCES administrative.ba_unit(id) ON UPDATE CASCADE ON DELETE Cascade;
CREATE INDEX notation_ba_unit_id_fk69_ind ON administrative.notation (ba_unit_id);

ALTER TABLE administrative.ba_unit_area ADD CONSTRAINT ba_unit_area_type_code_fk70 
            FOREIGN KEY (type_code) REFERENCES cadastre.area_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX ba_unit_area_type_code_fk70_ind ON administrative.ba_unit_area (type_code);

ALTER TABLE administrative.ba_unit_area ADD CONSTRAINT ba_unit_area_ba_unit_id_fk71 
            FOREIGN KEY (ba_unit_id) REFERENCES administrative.ba_unit(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX ba_unit_area_ba_unit_id_fk71_ind ON administrative.ba_unit_area (ba_unit_id);

ALTER TABLE administrative.rrr_share ADD CONSTRAINT rrr_share_rrr_id_fk72 
            FOREIGN KEY (rrr_id) REFERENCES administrative.rrr(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX rrr_share_rrr_id_fk72_ind ON administrative.rrr_share (rrr_id);

ALTER TABLE administrative.party_for_rrr ADD CONSTRAINT party_for_rrr_rrr_id_fk73 
            FOREIGN KEY (rrr_id,share_id) REFERENCES administrative.rrr_share(rrr_id,id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX party_for_rrr_rrr_id_fk73_ind ON administrative.party_for_rrr (rrr_id,share_id);

ALTER TABLE administrative.notation ADD CONSTRAINT notation_transaction_id_fk74 
            FOREIGN KEY (transaction_id) REFERENCES transaction.transaction(id) ON UPDATE CASCADE ON DELETE Cascade;
CREATE INDEX notation_transaction_id_fk74_ind ON administrative.notation (transaction_id);

ALTER TABLE administrative.source_describes_rrr ADD CONSTRAINT source_describes_rrr_source_id_fk75 
            FOREIGN KEY (source_id) REFERENCES source.source(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX source_describes_rrr_source_id_fk75_ind ON administrative.source_describes_rrr (source_id);

ALTER TABLE administrative.party_for_rrr ADD CONSTRAINT party_for_rrr_party_id_fk76 
            FOREIGN KEY (party_id) REFERENCES party.party(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX party_for_rrr_party_id_fk76_ind ON administrative.party_for_rrr (party_id);

ALTER TABLE transaction.transaction ADD CONSTRAINT transaction_status_code_fk77 
            FOREIGN KEY (status_code) REFERENCES transaction.transaction_status_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX transaction_status_code_fk77_ind ON transaction.transaction (status_code);

ALTER TABLE application.request_type ADD CONSTRAINT request_type_rrr_type_code_fk78 
            FOREIGN KEY (rrr_type_code) REFERENCES administrative.rrr_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX request_type_rrr_type_code_fk78_ind ON application.request_type (rrr_type_code);

ALTER TABLE application.request_type ADD CONSTRAINT request_type_type_action_code_fk79 
            FOREIGN KEY (type_action_code) REFERENCES application.type_action(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX request_type_type_action_code_fk79_ind ON application.request_type (type_action_code);

ALTER TABLE administrative.rrr ADD CONSTRAINT rrr_mortgage_type_code_fk80 
            FOREIGN KEY (mortgage_type_code) REFERENCES administrative.mortgage_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX rrr_mortgage_type_code_fk80_ind ON administrative.rrr (mortgage_type_code);

ALTER TABLE administrative.rrr ADD CONSTRAINT rrr_transaction_id_fk81 
            FOREIGN KEY (transaction_id) REFERENCES transaction.transaction(id) ON UPDATE CASCADE ON DELETE Cascade;
CREATE INDEX rrr_transaction_id_fk81_ind ON administrative.rrr (transaction_id);

ALTER TABLE administrative.ba_unit ADD CONSTRAINT ba_unit_transaction_id_fk82 
            FOREIGN KEY (transaction_id) REFERENCES transaction.transaction(id) ON UPDATE CASCADE ON DELETE Cascade;
CREATE INDEX ba_unit_transaction_id_fk82_ind ON administrative.ba_unit (transaction_id);

ALTER TABLE administrative.party_for_rrr ADD CONSTRAINT party_for_rrr_rrr_id_fk83 
            FOREIGN KEY (rrr_id) REFERENCES administrative.rrr(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX party_for_rrr_rrr_id_fk83_ind ON administrative.party_for_rrr (rrr_id);

ALTER TABLE administrative.notation ADD CONSTRAINT notation_rrr_id_fk84 
            FOREIGN KEY (rrr_id) REFERENCES administrative.rrr(id) ON UPDATE CASCADE ON DELETE Cascade;
CREATE INDEX notation_rrr_id_fk84_ind ON administrative.notation (rrr_id);

ALTER TABLE source.source ADD CONSTRAINT source_transaction_id_fk85 
            FOREIGN KEY (transaction_id) REFERENCES transaction.transaction(id) ON UPDATE CASCADE ON DELETE Cascade;
CREATE INDEX source_transaction_id_fk85_ind ON source.source (transaction_id);

ALTER TABLE source.source ADD CONSTRAINT source_status_code_fk86 
            FOREIGN KEY (status_code) REFERENCES transaction.reg_status_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX source_status_code_fk86_ind ON source.source (status_code);

ALTER TABLE cadastre.cadastre_object ADD CONSTRAINT cadastre_object_building_unit_type_code_fk87 
            FOREIGN KEY (building_unit_type_code) REFERENCES cadastre.building_unit_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX cadastre_object_building_unit_type_code_fk87_ind ON cadastre.cadastre_object (building_unit_type_code);

ALTER TABLE cadastre.cadastre_object ADD CONSTRAINT cadastre_object_transaction_id_fk88 
            FOREIGN KEY (transaction_id) REFERENCES transaction.transaction(id) ON UPDATE CASCADE ON DELETE Cascade;
CREATE INDEX cadastre_object_transaction_id_fk88_ind ON cadastre.cadastre_object (transaction_id);

ALTER TABLE cadastre.cadastre_object_target ADD CONSTRAINT cadastre_object_target_cadastre_object_id_fk89 
            FOREIGN KEY (cadastre_object_id) REFERENCES cadastre.cadastre_object(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX cadastre_object_target_cadastre_object_id_fk89_ind ON cadastre.cadastre_object_target (cadastre_object_id);

ALTER TABLE party.party ADD CONSTRAINT party_gender_code_fk90 
            FOREIGN KEY (gender_code) REFERENCES party.gender_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX party_gender_code_fk90_ind ON party.party (gender_code);

ALTER TABLE cadastre.survey_point ADD CONSTRAINT survey_point_transaction_id_fk91 
            FOREIGN KEY (transaction_id) REFERENCES transaction.transaction(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX survey_point_transaction_id_fk91_ind ON cadastre.survey_point (transaction_id);

ALTER TABLE cadastre.cadastre_object_target ADD CONSTRAINT cadastre_object_target_transaction_id_fk92 
            FOREIGN KEY (transaction_id) REFERENCES transaction.transaction(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX cadastre_object_target_transaction_id_fk92_ind ON cadastre.cadastre_object_target (transaction_id);

ALTER TABLE transaction.transaction_source ADD CONSTRAINT transaction_source_transaction_id_fk93 
            FOREIGN KEY (transaction_id) REFERENCES transaction.transaction(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX transaction_source_transaction_id_fk93_ind ON transaction.transaction_source (transaction_id);

ALTER TABLE transaction.transaction_source ADD CONSTRAINT transaction_source_source_id_fk94 
            FOREIGN KEY (source_id) REFERENCES source.source(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX transaction_source_source_id_fk94_ind ON transaction.transaction_source (source_id);

ALTER TABLE system.appuser_appgroup ADD CONSTRAINT appuser_appgroup_appuser_id_fk95 
            FOREIGN KEY (appuser_id) REFERENCES system.appuser(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX appuser_appgroup_appuser_id_fk95_ind ON system.appuser_appgroup (appuser_id);

ALTER TABLE system.appuser_appgroup ADD CONSTRAINT appuser_appgroup_appgroup_id_fk96 
            FOREIGN KEY (appgroup_id) REFERENCES system.appgroup(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX appuser_appgroup_appgroup_id_fk96_ind ON system.appuser_appgroup (appgroup_id);

ALTER TABLE system.approle_appgroup ADD CONSTRAINT approle_appgroup_approle_code_fk97 
            FOREIGN KEY (approle_code) REFERENCES system.approle(code) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX approle_appgroup_approle_code_fk97_ind ON system.approle_appgroup (approle_code);

ALTER TABLE system.approle_appgroup ADD CONSTRAINT approle_appgroup_appgroup_id_fk98 
            FOREIGN KEY (appgroup_id) REFERENCES system.appgroup(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX approle_appgroup_appgroup_id_fk98_ind ON system.approle_appgroup (appgroup_id);

ALTER TABLE application.application_action_type ADD CONSTRAINT application_action_type_next_status_type_code_fk99 
            FOREIGN KEY (next_status_type_code) REFERENCES application.application_status_type(code) ON UPDATE CASCADE ON DELETE Set null;
CREATE INDEX application_action_type_next_status_type_code_fk99_ind ON application.application_action_type (next_status_type_code);

ALTER TABLE system.br_validation ADD CONSTRAINT br_validation_target_action_type_code_fk100 
            FOREIGN KEY (target_action_type_code) REFERENCES application.application_action_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX br_validation_target_action_type_code_fk100_ind ON system.br_validation (target_action_type_code);

ALTER TABLE system.br_validation ADD CONSTRAINT br_validation_target_reg_moment_fk101 
            FOREIGN KEY (target_reg_moment) REFERENCES transaction.reg_status_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX br_validation_target_reg_moment_fk101_ind ON system.br_validation (target_reg_moment);

ALTER TABLE system.query_field ADD CONSTRAINT query_field_query_name_fk102 
            FOREIGN KEY (query_name) REFERENCES system.query(name) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX query_field_query_name_fk102_ind ON system.query_field (query_name);

ALTER TABLE system.config_map_layer ADD CONSTRAINT config_map_layer_pojo_query_name_fk103 
            FOREIGN KEY (pojo_query_name) REFERENCES system.query(name) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX config_map_layer_pojo_query_name_fk103_ind ON system.config_map_layer (pojo_query_name);

ALTER TABLE system.config_map_layer ADD CONSTRAINT config_map_layer_pojo_query_name_for_select_fk104 
            FOREIGN KEY (pojo_query_name_for_select) REFERENCES system.query(name) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX config_map_layer_pojo_query_name_for_select_fk104_ind ON system.config_map_layer (pojo_query_name_for_select);

ALTER TABLE cadastre.cadastre_object_node_target ADD CONSTRAINT cadastre_object_node_target_transaction_id_fk105 
            FOREIGN KEY (transaction_id) REFERENCES transaction.transaction(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX cadastre_object_node_target_transaction_id_fk105_ind ON cadastre.cadastre_object_node_target (transaction_id);

ALTER TABLE administrative.ba_unit_target ADD CONSTRAINT ba_unit_target_ba_unit_id_fk106 
            FOREIGN KEY (ba_unit_id) REFERENCES administrative.ba_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX ba_unit_target_ba_unit_id_fk106_ind ON administrative.ba_unit_target (ba_unit_id);

ALTER TABLE administrative.ba_unit_target ADD CONSTRAINT ba_unit_target_transaction_id_fk107 
            FOREIGN KEY (transaction_id) REFERENCES transaction.transaction(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX ba_unit_target_transaction_id_fk107_ind ON administrative.ba_unit_target (transaction_id);

ALTER TABLE system.map_search_option ADD CONSTRAINT map_search_option_query_name_fk108 
            FOREIGN KEY (query_name) REFERENCES system.query(name) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX map_search_option_query_name_fk108_ind ON system.map_search_option (query_name);

ALTER TABLE application.application_party ADD CONSTRAINT application_party_application_id_fk109 
            FOREIGN KEY (application_id) REFERENCES application.application(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_party_application_id_fk109_ind ON application.application_party (application_id);

ALTER TABLE application.application_party ADD CONSTRAINT application_party_party_id_fk110 
            FOREIGN KEY (party_id) REFERENCES party.party(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_party_party_id_fk110_ind ON application.application_party (party_id);

ALTER TABLE application.application_party ADD CONSTRAINT application_party_role_code_fk111 
            FOREIGN KEY (role_code) REFERENCES party.party_role_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_party_role_code_fk111_ind ON application.application_party (role_code);

ALTER TABLE application.application ADD CONSTRAINT application_request_code_fk112 
            FOREIGN KEY (request_code) REFERENCES application.request_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_request_code_fk112_ind ON application.application (request_code);

ALTER TABLE application.application_fee ADD CONSTRAINT application_fee_application_id_fk113 
            FOREIGN KEY (application_id) REFERENCES application.application(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_fee_application_id_fk113_ind ON application.application_fee (application_id);

ALTER TABLE application.application_fee ADD CONSTRAINT application_fee_fee_code_fk114 
            FOREIGN KEY (fee_code) REFERENCES application.fee_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_fee_fee_code_fk114_ind ON application.application_fee (fee_code);

ALTER TABLE application.request_type_fee_type ADD CONSTRAINT request_type_fee_type_request_code_fk115 
            FOREIGN KEY (request_code) REFERENCES application.request_type(code) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX request_type_fee_type_request_code_fk115_ind ON application.request_type_fee_type (request_code);

ALTER TABLE application.request_type_fee_type ADD CONSTRAINT request_type_fee_type_fee_code_fk116 
            FOREIGN KEY (fee_code) REFERENCES application.fee_type(code) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX request_type_fee_type_fee_code_fk116_ind ON application.request_type_fee_type (fee_code);

ALTER TABLE party.party ADD CONSTRAINT party_postal_address_id_fk117 
            FOREIGN KEY (postal_address_id) REFERENCES address.address(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX party_postal_address_id_fk117_ind ON party.party (postal_address_id);

ALTER TABLE party.party_id ADD CONSTRAINT party_id_party_id_fk118 
            FOREIGN KEY (party_id) REFERENCES party.party(id) ON UPDATE CASCADE ON DELETE Cascade;
CREATE INDEX party_id_party_id_fk118_ind ON party.party_id (party_id);

ALTER TABLE party.party_id ADD CONSTRAINT party_id_type_code_fk119 
            FOREIGN KEY (type_code) REFERENCES party.id_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX party_id_type_code_fk119_ind ON party.party_id (type_code);

ALTER TABLE application.application_action ADD CONSTRAINT application_action_type_code_fk120 
            FOREIGN KEY (type_code) REFERENCES application.application_action_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_action_type_code_fk120_ind ON application.application_action (type_code);

ALTER TABLE application.application_status ADD CONSTRAINT application_status_application_id_fk121 
            FOREIGN KEY (application_id) REFERENCES application.application(id) ON UPDATE CASCADE ON DELETE Cascade;
CREATE INDEX application_status_application_id_fk121_ind ON application.application_status (application_id);

ALTER TABLE application.application_status ADD CONSTRAINT application_status_type_code_fk122 
            FOREIGN KEY (type_code) REFERENCES application.application_status_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_status_type_code_fk122_ind ON application.application_status (type_code);

ALTER TABLE application.application_action ADD CONSTRAINT application_action_status_id_fk123 
            FOREIGN KEY (status_id) REFERENCES application.application_status(id) ON UPDATE CASCADE ON DELETE Cascade;
CREATE INDEX application_action_status_id_fk123_ind ON application.application_action (status_id);

ALTER TABLE application.request_type ADD CONSTRAINT request_type_starting_status_code_fk124 
            FOREIGN KEY (starting_status_code) REFERENCES application.application_status_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX request_type_starting_status_code_fk124_ind ON application.request_type (starting_status_code);

ALTER TABLE application.application_action_type ADD CONSTRAINT application_action_type_start_status_type_code_fk125 
            FOREIGN KEY (start_status_type_code) REFERENCES application.application_status_type(code) ON UPDATE CASCADE ON DELETE Cascade;
CREATE INDEX application_action_type_start_status_type_code_fk125_ind ON application.application_action_type (start_status_type_code);

ALTER TABLE application.application_spatial_unit ADD CONSTRAINT application_spatial_unit_application_id_fk126 
            FOREIGN KEY (application_id) REFERENCES application.application(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX application_spatial_unit_application_id_fk126_ind ON application.application_spatial_unit (application_id);

ALTER TABLE application.application_spatial_unit ADD CONSTRAINT application_spatial_unit_spatial_unit_id_fk127 
            FOREIGN KEY (spatial_unit_id) REFERENCES cadastre.spatial_unit(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX application_spatial_unit_spatial_unit_id_fk127_ind ON application.application_spatial_unit (spatial_unit_id);

ALTER TABLE transaction.transaction ADD CONSTRAINT transaction_from_application_id_fk128 
            FOREIGN KEY (from_application_id) REFERENCES application.application(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX transaction_from_application_id_fk128_ind ON transaction.transaction (from_application_id);

ALTER TABLE source.deed ADD CONSTRAINT deed_id_fk129 
            FOREIGN KEY (id) REFERENCES source.source(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX deed_id_fk129_ind ON source.deed (id);

ALTER TABLE source.deed ADD CONSTRAINT deed_instrument_type_code_fk130 
            FOREIGN KEY (instrument_type_code) REFERENCES administrative.rrr_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX deed_instrument_type_code_fk130_ind ON source.deed (instrument_type_code);

ALTER TABLE source.deed ADD CONSTRAINT deed_first_party_id_fk131 
            FOREIGN KEY (first_party_id) REFERENCES party.party(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX deed_first_party_id_fk131_ind ON source.deed (first_party_id);

ALTER TABLE source.deed ADD CONSTRAINT deed_second_party_id_fk132 
            FOREIGN KEY (second_party_id) REFERENCES party.party(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX deed_second_party_id_fk132_ind ON source.deed (second_party_id);

ALTER TABLE source.deed ADD CONSTRAINT deed_forward_reference_id_fk133 
            FOREIGN KEY (forward_reference_id) REFERENCES source.deed(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX deed_forward_reference_id_fk133_ind ON source.deed (forward_reference_id);

ALTER TABLE source.deed ADD CONSTRAINT deed_backward_reference_id_fk134 
            FOREIGN KEY (backward_reference_id) REFERENCES source.deed(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX deed_backward_reference_id_fk134_ind ON source.deed (backward_reference_id);

ALTER TABLE cadastre.district ADD CONSTRAINT district_region_id_fk135 
            FOREIGN KEY (region_id) REFERENCES cadastre.region(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX district_region_id_fk135_ind ON cadastre.district (region_id);

ALTER TABLE cadastre.section ADD CONSTRAINT section_district_id_fk136 
            FOREIGN KEY (district_id) REFERENCES cadastre.district(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX section_district_id_fk136_ind ON cadastre.section (district_id);

ALTER TABLE cadastre.block ADD CONSTRAINT block_section_id_fk137 
            FOREIGN KEY (section_id) REFERENCES cadastre.section(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX block_section_id_fk137_ind ON cadastre.block (section_id);

ALTER TABLE cadastre.cadastre_object ADD CONSTRAINT cadastre_object_found_in_cadastre_object_id_fk138 
            FOREIGN KEY (found_in_cadastre_object_id) REFERENCES cadastre.cadastre_object(id) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX cadastre_object_found_in_cadastre_object_id_fk138_ind ON cadastre.cadastre_object (found_in_cadastre_object_id);

ALTER TABLE source.deed ADD CONSTRAINT deed_land_use_code_fk139 
            FOREIGN KEY (land_use_code) REFERENCES source.land_use_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX deed_land_use_code_fk139_ind ON source.deed (land_use_code);

ALTER TABLE party.party ADD CONSTRAINT party_nationality_code_fk140 
            FOREIGN KEY (nationality_code) REFERENCES party.country(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX party_nationality_code_fk140_ind ON party.party (nationality_code);

ALTER TABLE source.power_of_attorney ADD CONSTRAINT power_of_attorney_id_fk141 
            FOREIGN KEY (id) REFERENCES source.source(id) ON UPDATE CASCADE ON DELETE CASCADE;
CREATE INDEX power_of_attorney_id_fk141_ind ON source.power_of_attorney (id);

ALTER TABLE system.appuser ADD CONSTRAINT appuser_office_code_fk142 
            FOREIGN KEY (office_code) REFERENCES system.office(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX appuser_office_code_fk142_ind ON system.appuser (office_code);

ALTER TABLE application.application_status_type ADD CONSTRAINT application_status_type_office_code_fk143 
            FOREIGN KEY (office_code) REFERENCES system.office(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_status_type_office_code_fk143_ind ON application.application_status_type (office_code);

ALTER TABLE application.application_action_type ADD CONSTRAINT application_action_type_operation_fk144 
            FOREIGN KEY (operation) REFERENCES application.operation_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX application_action_type_operation_fk144_ind ON application.application_action_type (operation);

ALTER TABLE system.br_validation ADD CONSTRAINT br_validation_target_operation_code_fk145 
            FOREIGN KEY (target_operation_code) REFERENCES application.operation_type(code) ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE INDEX br_validation_target_operation_code_fk145_ind ON system.br_validation (target_operation_code);
--Generate triggers for tables --
-- triggers for table source.source -- 

 

CREATE OR REPLACE FUNCTION source.f_for_tbl_source_trg_change_of_status() RETURNS TRIGGER 
AS $$
begin
  if old.status_code is not null and old.status_code = 'pending' and new.status_code in ( 'current', 'historic') then
      update source.source set 
      status_code= 'previous', change_user=new.change_user
      where la_nr= new.la_nr and status_code = 'current';
  end if;
  return new;
end;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_change_of_status ON source.source CASCADE;
CREATE TRIGGER trg_change_of_status before update
   ON source.source FOR EACH ROW
   EXECUTE PROCEDURE source.f_for_tbl_source_trg_change_of_status();
    
-- triggers for table administrative.rrr -- 

 

CREATE OR REPLACE FUNCTION administrative.f_for_tbl_rrr_trg_change_from_pending() RETURNS TRIGGER 
AS $$
begin
  if old.status_code = 'pending' and new.status_code in ( 'current', 'historic') then
    update administrative.rrr set 
      status_code= 'previous', change_user=new.change_user
    where ba_unit_id= new.ba_unit_id and nr= new.nr and status_code = 'current';
  end if;
  return new;
end;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_change_from_pending ON administrative.rrr CASCADE;
CREATE TRIGGER trg_change_from_pending before update
   ON administrative.rrr FOR EACH ROW
   EXECUTE PROCEDURE administrative.f_for_tbl_rrr_trg_change_from_pending();
    
-- triggers for table application.application -- 

 

CREATE OR REPLACE FUNCTION application.f_for_tbl_application_trg_new() RETURNS TRIGGER 
AS $$
begin
  if new.request_code is not null then
    new.expected_completion_date = new.lodging_datetime 
     + (select (nr_days_to_complete::varchar || ' days')::interval 
         from application.request_type 
         where code = new.request_code);
  end if;
  return new;
end;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_new ON application.application CASCADE;
CREATE TRIGGER trg_new before insert
   ON application.application FOR EACH ROW
   EXECUTE PROCEDURE application.f_for_tbl_application_trg_new();
    

CREATE OR REPLACE FUNCTION application.f_for_tbl_application_trg_after_new() RETURNS TRIGGER 
AS $$
begin
  -- For the new application insert a starting record in the application_status
  insert into application.application_status(id, application_id, type_code, change_user)
  select uuid_generate_v1(), new.id, starting_status_code, new.change_user
  from application.request_type rt 
  where code = new.request_code;
  return new;
end;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_after_new ON application.application CASCADE;
CREATE TRIGGER trg_after_new after insert
   ON application.application FOR EACH ROW
   EXECUTE PROCEDURE application.f_for_tbl_application_trg_after_new();
    
-- triggers for table cadastre.cadastre_object -- 

 

CREATE OR REPLACE FUNCTION cadastre.f_for_tbl_cadastre_object_trg_remove() RETURNS TRIGGER 
AS $$
BEGIN
  delete from cadastre.spatial_unit where id=old.id;
  return old;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_remove ON cadastre.cadastre_object CASCADE;
CREATE TRIGGER trg_remove before delete
   ON cadastre.cadastre_object FOR EACH ROW
   EXECUTE PROCEDURE cadastre.f_for_tbl_cadastre_object_trg_remove();
    

CREATE OR REPLACE FUNCTION cadastre.f_for_tbl_cadastre_object_trg_new() RETURNS TRIGGER 
AS $$
BEGIN
  if (select count(*)=0 from cadastre.spatial_unit where id=new.id) then
    insert into cadastre.spatial_unit(id, rowidentifier, change_user) 
    values(new.id, new.rowidentifier,new.change_user);
  end if;
  if new.type_code != 'strata' and (new.name_lastpart is null or new.name_lastpart like 'tmp%') then
    new.name_lastpart = cadastre.get_last_part(new.name_firstpart);
  end if;
  return new;
END;

$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_new ON cadastre.cadastre_object CASCADE;
CREATE TRIGGER trg_new before insert
   ON cadastre.cadastre_object FOR EACH ROW
   EXECUTE PROCEDURE cadastre.f_for_tbl_cadastre_object_trg_new();
    

CREATE OR REPLACE FUNCTION cadastre.f_for_tbl_cadastre_object_trg_geommodify() RETURNS TRIGGER 
AS $$
declare
  rec record;
  rec_snap record;
  tolerance float;
  modified_geom geometry;
begin

  if new.status_code != 'current' then
    return new;
  end if;

  if new.type_code not in (select code from cadastre.cadastre_object_type where in_topology) then
    return new;
  end if;

  tolerance = coalesce(system.get_setting('map-tolerance')::double precision, 0.01);
  for rec in select co.id, co.geom_polygon 
                 from cadastre.cadastre_object co 
                 where  co.id != new.id and co.type_code = new.type_code and co.status_code = 'current'
                     and co.geom_polygon is not null 
                     and new.geom_polygon && co.geom_polygon 
                     and st_dwithin(new.geom_polygon, co.geom_polygon, tolerance)
  loop
    modified_geom = cadastre.add_topo_points(new.geom_polygon, rec.geom_polygon);
    if not st_equals(modified_geom, rec.geom_polygon) then
      update cadastre.cadastre_object 
        set geom_polygon= modified_geom, change_user= new.change_user 
      where id= rec.id;
    end if;
  end loop;
  return new;
end;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_geommodify ON cadastre.cadastre_object CASCADE;
CREATE TRIGGER trg_geommodify after insert or update of geom_polygon
   ON cadastre.cadastre_object FOR EACH ROW
   EXECUTE PROCEDURE cadastre.f_for_tbl_cadastre_object_trg_geommodify();
    
-- triggers for table application.application_fee -- 

 

CREATE OR REPLACE FUNCTION application.f_for_tbl_application_fee_trg_after_change() RETURNS TRIGGER 
AS $$
begin
  update application.application set 
    total_fee = tt.total_amount,
    total_amount_paid = tt.paid_amount
  from (select sum(total_amount) as total_amount, sum(paid_amount) as paid_amount from application.application_fee af
    where af.application_id = new.application_id) tt
  where id= new.application_id;
  return new;
end;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_after_change ON application.application_fee CASCADE;
CREATE TRIGGER trg_after_change after insert or update
   ON application.application_fee FOR EACH ROW
   EXECUTE PROCEDURE application.f_for_tbl_application_fee_trg_after_change();
    
-- triggers for table application.application_status -- 

 

CREATE OR REPLACE FUNCTION application.f_for_tbl_application_status_trg_change() RETURNS TRIGGER 
AS $$
begin
  if not new.is_current and old.is_current then
    new.date_leave = now();
  end if;
  return new;
end;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_change ON application.application_status CASCADE;
CREATE TRIGGER trg_change before update
   ON application.application_status FOR EACH ROW
   EXECUTE PROCEDURE application.f_for_tbl_application_status_trg_change();
    

CREATE OR REPLACE FUNCTION application.f_for_tbl_application_status_trg_after_new() RETURNS TRIGGER 
AS $$
declare
  assignee_id_v varchar;
begin
  -- After the status has been added, add the whole list of actions related to that status
  insert into application.application_action(id, status_id, type_code, action_order, change_user)
  select uuid_generate_v1(), new.id, code, action_order, new.change_user
  from application.application_action_type 
  where status = 'c' and start_status_type_code= new.type_code;
  -- It assigns the application to the head of the office where the application is moved.
  if (select count(*) from application.application_status where application_id = new.application_id)>1 then
    assignee_id_v = (select u.id from system.appuser u 
      inner join application.application_status_type s on u.office_code= s.office_code and u.office_head
      where s.code = new.type_code);
  else
    assignee_id_v = (select u.id from system.appuser u where u.username= new.change_user);
  end if;
  update application.application set 
    assignee_id = assignee_id_v, assigned_datetime = now()
  where id= new.application_id;
  return new;
end;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_after_new ON application.application_status CASCADE;
CREATE TRIGGER trg_after_new after insert
   ON application.application_status FOR EACH ROW
   EXECUTE PROCEDURE application.f_for_tbl_application_status_trg_after_new();
    

--Extra modifications added to the script that cannot be generated --

insert into system.approle_appgroup (approle_code, appgroup_id)
SELECT r.code, 'super-group' FROM system.approle r
where r.code not ilike 'Manage%' and r.code not in (select approle_code from system.approle_appgroup g where appgroup_id in ( 'super-group', 'admin-group') );

insert into system.appuser_appgroup (appuser_id, appgroup_id)
select u.id, g.id
from system.appuser u, system.appgroup g
where u.id != 'admin' and g.id !='admin-group' 
  and (u.id, g.id) not in (select appuser_id, appgroup_id from system.appuser_appgroup );

--Make the function ST_MakeBox3D(geometry, geometry) RETURNS box3d if it does not exist. The function does not exist if Postgis 2.0 is used

create or replace function make_function_ST_MakeBox3D() returns void
as
$$
begin
  if (select count(*)=0 from pg_proc where proname='st_makebox3d') then
    CREATE OR REPLACE FUNCTION ST_MakeBox3D(geometry, geometry)
      RETURNS box3d AS 'SELECT ST_3DMakeBox($1, $2)'
    LANGUAGE 'sql' IMMUTABLE STRICT;
  end if;
end;
$$
language 'plpgsql';


select make_function_ST_MakeBox3D();

drop function make_function_ST_MakeBox3D();

--This function is used to multiply values from a set or rows. It is used to sum the shares.
--Based in an example found in http://a-kretschmer.de/diverses.shtml

DROP FUNCTION IF EXISTS multiply_agg_step(int,int) CASCADE;
CREATE FUNCTION multiply_agg_step(int,int) RETURNS int 
AS ' select $1 * $2; ' 
language sql IMMUTABLE STRICT; 

CREATE AGGREGATE multiply_agg (basetype=int, sfunc=multiply_agg_step, stype=int, initcond=1 ) ;

-------View cadastre.survey_control ---------
DROP VIEW IF EXISTS cadastre.survey_control CASCADE;
CREATE VIEW cadastre.survey_control AS SELECT su.id, su.label, su.geom
FROM cadastre.level l, cadastre.spatial_unit su 
WHERE l.id = su.level_id AND l.name = 'Survey Control';;

-------View cadastre.road ---------
DROP VIEW IF EXISTS cadastre.road CASCADE;
CREATE VIEW cadastre.road AS SELECT su.id, su.label, su.geom
FROM cadastre.level l, cadastre.spatial_unit su 
WHERE l.id= su.level_id AND l.name = 'Roads';;

-------View cadastre.place_name ---------
DROP VIEW IF EXISTS cadastre.place_name CASCADE;
CREATE VIEW cadastre.place_name AS SELECT su.id, su.label, su.geom
FROM cadastre.level l, cadastre.spatial_unit su 
WHERE l.id = su.level_id AND l.name = 'Place Names';;

-------View system.user_roles ---------
DROP VIEW IF EXISTS system.user_roles CASCADE;
CREATE VIEW system.user_roles AS SELECT u.username, rg.approle_code as rolename
   FROM system.appuser u
   JOIN system.appuser_appgroup ug ON (u.id = ug.appuser_id and u.active)
   JOIN system.approle_appgroup rg ON ug.appgroup_id = rg.appgroup_id
;

-------View application.application_log ---------
DROP VIEW IF EXISTS application.application_log CASCADE;
CREATE VIEW application.application_log AS SELECT a_a.id, a_s.application_id, a_a.type_code AS action_type, a_s.type_code AS status_type, a_a.remarks, a_a.change_time, 
(appuser.first_name || ' ') || appuser.last_name AS user_fullname
   FROM application.application_action a_a
   JOIN application.application_status a_s ON a_a.status_id = a_s.id
   JOIN system.appuser ON a_a.change_user = appuser.id;

-------View system.br_current ---------
DROP VIEW IF EXISTS system.br_current CASCADE;
CREATE VIEW system.br_current AS select b.id, b.technical_type_code, b.feedback, bd.body
from system.br b inner join system.br_definition bd on b.id= bd.br_id
where now() between bd.active_from and bd.active_until;

-------View system.br_report ---------
DROP VIEW IF EXISTS system.br_report CASCADE;
CREATE VIEW system.br_report AS SELECT  b.id, b.technical_type_code, b.feedback, b.description,
CASE WHEN target_code = 'application-action' THEN bv.target_action_type_code
ELSE bv.target_reg_moment
END AS moment_code,
bd.body, bv.severity_code, bv.target_code, bv.target_request_type_code, 
bv.target_rrr_type_code, bv.order_of_execution
FROM system.br b
  LEFT OUTER JOIN system.br_validation bv  ON b.id = bv.br_id
  JOIN system.br_definition bd ON b.id = bd.br_id
WHERE now() >= bd.active_from AND now() <= bd.active_until
order by b.id;

-------View application.application_search_result ---------
DROP VIEW IF EXISTS application.application_search_result CASCADE;
CREATE VIEW application.application_search_result AS SELECT a.id, a.nr, a.lodging_datetime, a.expected_completion_date, a.assignee_id, a.assigned_datetime, a.total_fee, a.total_amount_paid, 
  a.request_code, (COALESCE(u.first_name, '') || ' ') || COALESCE(u.last_name, '') AS assignee_name, 
  application.get_application_parties(a.id, true) as applicants, 
  ast.display_value AS status_display_value
FROM application.application a
  JOIN application.application_status a_s ON a.id = a_s.application_id AND a_s.is_current
  JOIN application.application_status_type ast ON ast.code = a_s.type_code
  LEFT JOIN system.appuser u ON a.assignee_id = u.id;

-------View application.plan_certification_request ---------
DROP VIEW IF EXISTS application.plan_certification_request CASCADE;
CREATE VIEW application.plan_certification_request AS select a.id as application_id, a_s_u.spatial_unit_id
from application.application a inner join application.application_spatial_unit a_s_u on a.id = a_s_u.application_id
  inner join application.application_status a_s on a.id = a_s.application_id and a_s.is_current
where a.request_code = 'smd-plancertification' 
and (a_s.type_code in (select code from application.application_status_type where not is_terminal) or a_s.type_code = 'smd-plancertification-completed');


-- Scan tables and views for geometry columns                 and populate geometry_columns table

SELECT Populate_Geometry_Columns();
