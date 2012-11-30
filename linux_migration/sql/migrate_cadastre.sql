﻿--Create handy views
--View that gives the districts
drop table if exists staging_area.district_source  cascade;
create table staging_area.district_source as 
select region as region_id, distric_nr as num, 'District ' || distric_nr as locality, 
coalesce(year_declared, 0) as year_declared, st_geometryn(the_geom,1) as the_geom 
from staging_area.district
where the_geom is null or st_isvalid(the_geom);

drop table if exists staging_area.block_source;
create table staging_area.block_source as 
select b.region, substring(b.district from 3 for 2) as district, 
substring(b.section  from 2 for 3) as section_num, blockno, st_geometryn(b.geom,1) as the_geom
from staging_area.shape_block b
where st_isvalid(b.geom) and blockno is not null;

--View that gives the sections
drop table if exists staging_area.section_source;
create table staging_area.section_source as 
select b.region, b.district, section_num as num, st_union(the_geom) as the_geom
from staging_area.block_source b
group by b.region, b.district, b.section_num;


--View that gives the parcels
drop table if exists staging_area.parcel_source;
create table staging_area.parcel_source as 
select 
b.region || '/' || b.district || '/' || b.section_num || '/' || b.blockno || '/' || l.lotno as id, 
'parcel' as type_code,
b.region || '/' || b.district || '/' || b.section_num || '/' || b.blockno as name_firstpart,
l.lotno as name_lastpart,
'current' as status_code,
st_transform(st_geometryn(l.geom,1), 32630) as geom_polygon,
'migration-transaction' as transaction_id
from staging_area.shape_lot l, staging_area.block_source b
where st_isvalid(l.geom) and l.lotno != '9999' 
  and l.geom && b.the_geom and st_intersects(st_centroid(l.geom), b.the_geom);

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
from staging_area.district_source;

-- Insert sections.
insert into cadastre.section(id, district_id, num, the_geom)
select s.region || '/' || s.district || '/' || s.num as id, s.region || '/' || s.district as district_id, 
s.num, st_transform(s.the_geom,32630)
from staging_area.section_source s;

-- Insert blocks. 

insert into cadastre.block(id, section_id, num, the_geom)
select region || '/' || district || '/' || section_num || '/' || blockno as id, 
region || '/' || district || '/' || section_num  as section_id, 
blockno as num,  st_transform(the_geom, 32630) as the_geom
from staging_area.block_source b; 

-- Insert parcels. It excludes parcels that miss part of the identifier or their identifier is used more than once or the geometry is not valid
insert into cadastre.cadastre_object(id, type_code, name_firstpart, name_lastpart, status_code, geom_polygon, transaction_id)
select id, type_code, name_firstpart, name_lastpart, status_code, geom_polygon, transaction_id
from staging_area.parcel_source 
where id not in (select id
  from staging_area.parcel_source
  group by id
  having count(*)>1);

--Insert official area and calculated area for each parcel. The area is retrieved from the geometry
insert into cadastre.spatial_value_area(spatial_unit_id, type_code, size) 
select id, 'officialArea', st_area(geom_polygon) from cadastre.cadastre_object;
insert into cadastre.spatial_value_area(spatial_unit_id, type_code, size) 
select id, 'calculatedArea', st_area(geom_polygon) from cadastre.cadastre_object;


