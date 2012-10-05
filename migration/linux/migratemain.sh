#!/bin/bash
db_host=$1
db_port=$2
db_name=$3
db_user=$4
district_source=$5
district_destination=$6
section_source=$7
section_destination=$8
migrate_spatial=$9
srid=2136
region="GA"


#migrate sections to staging_area

echo "Conveting sections"
echo "*****************************************************************************"
    ./convertall.sh  $db_host  $db_port $db_name $db_user $region $srid $section_source $section_destination 2>>logs/mainlogs  
echo "Done with sections"
echo "******************************************************************************"


#migrate districts to staging_area
 

echo "Conveting districts" 
echo "*****************************************************************************"
   ./migratedistrict.sh $db_host $db_port $db_name  $db_user $srid  $district_source $district_destination

echo "Done with districtsi"
echo "******************************************************************************"


#migrate from staging_area to cadastre schema
psql $extra_options--host=$db_host --port=$db_port --username=$db_user --dbname=$db_name --file=$migrate_spatial --log-file=logs/migrate_spatial

