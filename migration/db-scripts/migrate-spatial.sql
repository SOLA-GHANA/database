--Create handy views
--View that gives the parcels
create or replace view staging_area.parcel as 
select 
b.region || '/' || substring(b.section  from 2 for 3) || '/' || b.blockno || '/' || l.lotno as id, 
'parcel' as type_code,
b.region || '/' || substring(b.section  from 2 for 3) || '/' || b.blockno as name_firstpart,
l.lotno as name_lastpart,
'current' as status_code,
st_transform(st_geometryn(l.geom,1), 32630) as geom_polygon,
'migration-transaction' as transaction_id
from staging_area.shape_lot l, staging_area.shape_block b
where l.lotno != '9999' and l.geom && b.geom and st_intersects(st_centroid(l.geom), b.geom);

-- Create a view that is used to retrieve duplications
drop view if exists staging_area.parcel_duplications;
create view staging_area.parcel_duplications as 
select name_firstpart as region_section_block, name_lastpart as parcel_nr, count(*) as nr_of_duplications
from staging_area.parcel
group by name_firstpart, name_lastpart 
having count(*)>1
order by 1,2;

--Empty the table where the data about regions, districts, rections and blocks are stored
delete from cadastre.spatial_unit_group;
--Empty the table where the data about parcels are stored
delete from cadastre.spatial_unit;
--Empty the transaction table
delete from transaction.transaction;

-- Create a new transaction only for the migration
insert into transaction.transaction(id, status_code, approval_datetime) values('migration-transaction', 'approved', now());

-- Insert regions. Regions have hierarchy 1
insert into cadastre.spatial_unit_group(id, hierarchy_level, label, name, geom)
select 
code as id, 
1 as hierarchy_level, 
name as label, 
name as name, 
st_multi(st_transform(the_geom,32630)) as geom 
from staging_area.region
where the_geom is not null and st_isvalid(the_geom);

-- Insert districts. Districts have hierarchy 2
insert into cadastre.spatial_unit_group(id, hierarchy_level, label, name, geom)
select 
region || '/' || district_nr as id, 
2 as hierarchy_level, 
district_nr as label, 
region || '/' || district_nr as name, 
st_multi(st_transform(the_geom,32630)) as geom
from staging_area.district
where the_geom is not null and st_isvalid(the_geom);

-- Insert sections. Sections have hierarchy 3

-- Insert blocks. Blocks have hierarchy 4

-- Insert parcels. It excludes parcels that miss part of the identifier or their identifier is used more than once or the geometry is not valid
insert into cadastre.cadastre_object(id, type_code, name_firstpart, name_lastpart, status_code, geom_polygon, transaction_id)
select id, type_code, name_firstpart, name_lastpart, status_code, geom_polygon, transaction_id
from staging_area.parcel
where id not in (select id
  from staging_area.parcel  
  group by id
  having count(*)>1);

--Insert official area and calculated area for each parcel. The area is retrieved from the geometry
insert into cadastre.spatial_value_area(spatial_unit_id, type_code, size) 
select id, 'officialArea', st_area(geom_polygon) from cadastre.cadastre_object;
insert into cadastre.spatial_value_area(spatial_unit_id, type_code, size) 
select id, 'calculatedArea', st_area(geom_polygon) from cadastre.cadastre_object;
