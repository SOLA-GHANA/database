#!/bin/bash
db_host=$1	
db_port=$2
db_name=$3
db_user=$4
srid=$5
region=$6
src_dir=$7
dest_dir=$8


psql --host=$db_host --port=$db_port --username=$db_user  --dbname=$db_name --command="delete from staging_area.shape_block"
psql --host=$db_host --port=$db_port --username=$db_user --dbname=$db_name --command="delete from staging_area.shape_lot"

#loops through source and destination files and executed convertsingle.sh
#errors are appeneded to logs file

for file in $( ls $src_dir )
do
 if [ "${file##*.}"="ZIP" ]
 then 
   echo  `date` >> logs/districtlogs
   echo "${file%.*}" >> logs/districtlogs
   ./convertsingle.sh  "${file%.*}"  $db_host $db_port $db_name $db_user $srid $region $src_dir $dest_dir 2>> logs/districtlogs 
 else
	echo "files in source directory must end with .ZIP"
	echo error in processing $file >> logs
	exit 1
 fi 
done
