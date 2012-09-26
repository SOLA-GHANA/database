#!/bin/bash
districtnr=$1
db_host=$2
db_port=$3
db_name=$4
db_user=$5
region=$6
srid=2136
src_dir=$7
dest_dir=$8
extra_options=--quiet -v ON_ERROR_STOP=1 

#verify that the destination directory is  valid including write access
#otherwise exit and log
#guard against nonexistent

#test number of arguements
if [$@ -ne 8]
then 
	echo "Number of arguements must be equal to eight" 
	exit 1
fi

if [ -d "$dest_dir/$districtnr" ]
then
	    rm -rf $dest_dir/$districtnr
fi

unzip  $src_dir/$districtnr.ZIP  -d $dest_dir

#-g geom to match to the staging_area 
shp2pgsql -a -s $srid -g geom $dest_dir/$districtnr/D${districtnr#*t}.shp staging_area.districts > $dest_dir/tmp.sql
psql $extra_options--host=$db_host --port=$db_port --username=$db_user --dbname=$db_name --file=$dest_dir/tmp.sql

#stage 4 run insert statements against  target database
psql %extra_options$--host=%db_host$--port=%db_port$--username=%db_user$--dbname=%db_name$--file=$dest_dir/tmp.sql

if [ -d $dest_dir/$districtnr ]
  then
    rm -rf $dest_dir/$districtnr
fi
