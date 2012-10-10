--Empty the table where the data about regions, districts, rections and blocks are stored
delete from cadastre.block;
delete from cadastre.section;
delete from cadastre.district;
delete from cadastre.region;

--Empty the table where the data about parcels are stored
delete from cadastre.spatial_unit;

--Empty the transaction table
delete from transaction.transaction;

-- Create a new transaction only for the migration
insert into transaction.transaction(id, status_code, approval_datetime) values('migration-transaction', 'approved', now());

-- Insert regions
insert into cadastre.region(id, code, name, the_geom)
select distinct
case when code = 'AA' then 'GA' else code end as id, 
case when code = 'AA' then 'GA' else code end,
name, 
st_transform(the_geom,32630) as the_geom 
from staging_area.region
where the_geom is not null and st_isvalid(the_geom);

-- Insert districts
insert into cadastre.district(id, region_id, num, year_declared, the_geom)
select 
region_id || '/' || num as id, 
region_id,
num,year_declared, 
st_transform(the_geom,32630) 
as the_geom
from staging_area.district_source
where the_geom is not null and st_isvalid(the_geom);

-- Insert sections.
insert into cadastre.section(id, district_id, num, the_geom)
select s.region || '/' || d.num || '/' || s.num as id, s.region || '/' || d.num as district_id, 
s.num, st_transform(s.the_geom,32630)
from staging_area.section_source s inner join staging_area.district_source d on st_intersects(st_centroid(s.the_geom), d.the_geom);

-- Insert blocks. 
insert into cadastre.block(id, section_id, num, the_geom)
select s.id || '/' || b.blockno as id, s.id as section_id, blockno as num,  st_geometryn(st_union(st_transform(b.geom, 32630)),1) as the_geom
from staging_area.shape_block b inner join cadastre.section s on st_intersects(st_transform(st_centroid(b.geom), 32630), s.the_geom)
group by s.id, blockno; 

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


