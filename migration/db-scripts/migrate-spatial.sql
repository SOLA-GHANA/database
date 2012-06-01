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
region_nr as id, 
1 as hierarchy_level, 
region_nr as label, 
region_nr as name, 
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
insert into cadastre.spatial_unit_group(id, hierarchy_level, label, name, geom)
select 
region || '/' || district || '/' || section_nr as id, 
3 as hierarchy_level, 
section_nr as label, 
region || '/' || district || '/' || section_nr as name, 
st_multi(st_transform(the_geom,32630)) as geom
from staging_area.section
where the_geom is not null and st_isvalid(the_geom);

-- Insert blocks. Blocks have hierarchy 4
insert into cadastre.spatial_unit_group(id, hierarchy_level, label, name, geom)
select 
region || '/' || district || '/' || section  || '/' || block_nr as id, 
4 as hierarchy_level, 
block_nr as label, 
region || '/' || district || '/' || section  || '/' || block_nr as name, 
st_multi(st_transform(the_geom,32630)) as geom
from staging_area.block
where the_geom is not null and st_isvalid(the_geom);

-- Insert parcels. It excludes parcels that miss part of the identifier or their identifier is used more than once or the geometry is not valid
insert into cadastre.cadastre_object(id, type_code, name_firstpart, name_lastpart, status_code, geom_polygon, transaction_id)
select 
region || '/' || district || '/' || section  || '/' || block || '/' || parcel_nr as id, 
'parcel' as type_code,
region || '/' || district || '/' || section  || '/' || block as name_firstpart,
parcel_nr as name_lastpart,
'current' as status_code,
the_geom as geom_polygon,
'migration-transaction' as transaction_id
from staging_area.parcel_utm
where the_geom is not null and st_isvalid(the_geom) 
and (region || '/' || district || '/' || section  || '/' || block || '/' || parcel_nr) is not null
and (region || '/' || district || '/' || section  || '/' || block || '/' || parcel_nr) 
  in (select (region || '/' || district || '/' || section  || '/' || block || '/' || parcel_nr) 
      from staging_area.shape_lot 
      group by (region || '/' || district || '/' || section  || '/' || block || '/' || parcel_nr) having count(*)=1);

--Insert official area and calculated area for each parcel. The area is retrieved from the geometry
insert into cadastre.spatial_value_area(spatial_unit_id, type_code, size) 
select id, 'officialArea', st_area(geom_polygon) from cadastre.cadastre_object;
insert into cadastre.spatial_value_area(spatial_unit_id, type_code, size) 
select id, 'calculatedArea', st_area(geom_polygon) from cadastre.cadastre_object;
