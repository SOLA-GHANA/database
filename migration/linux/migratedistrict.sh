#!/bin/bash
db_host=$1
db_port=$2
db_name=$3
db_user=$4
srid=$5
src_dir=$6
dest_dir=$7
extra_options=--quiet  ON_ERROR_STOP=1 

#loops through source and destination files and executed singldistricts.sh
#errors are appeneded to logs file

psql $extra_options --host=$db_host --port=$db_port --username=$db_user --dbname=$db_name --command="delete from staging_area.district"

for file in $( ls $src_dir )
do
 if [ "${file##*.}"="ZIP" ]
 then 
   echo  `date` >> logs/districtlogs
   echo "${file%.*}" >> logs/districtlogs
   ./singledistricts.sh  "${file%.*}"   $db_host $db_port $db_name  $db_user  $srid  $src_dir $dest_dir  2>> logs/districtlogs 
 else
	echo "files in source directory must end with .ZIP"
	echo error in processing $file > logs/disrictlogs
	exit 1
 fi 
done
