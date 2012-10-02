#!/bin/bash
sectionnr=$1
db_host=$2
db_port=$3
db_name=$4
db_user=$5
region=$6
srid=$7
src_dir=$8
dest_dir=$9
extra_options=--quiet -v ON_ERROR_STOP=1 

#verify that the destination directory is  valid including write access
#otherwise exit and log
#guard against nonexistent

#test number of arguements
if [ $# -ne 9 ]
then 
	echo "Number of arguements must be equal to nine\n" 
	echo $#
	exit 2
fi

rm -rf $dest_dir/$sectionnr
mkdir $dest_dir/$sectionnr
unzip  $src_dir/$sectionnr.ZIP  -d $dest_dir/$sectionnr


avcimport $dest_dir/$sectionnr/LOT.E00 $dest_dir/$sectionnr/cov_lot
avcimport $dest_dir/$sectionnr/BLOCK.E00 $dest_dir/$sectionnr/cov_block

ogr2ogr -f "ESRI Shapefile" -skipfailures -overwrite $dest_dir/$sectionnr/shape_lot $dest_dir/$sectionnr/cov_lot
ogr2ogr -f "ESRI Shapefile" -skipfailures -overwrite $dest_dir/$sectionnr/shape_block $dest_dir/$sectionnr/cov_block

#-g geom to match to the staging_area 
shp2pgsql -a -s $srid -g geom $dest_dir/$sectionnr/shape_block/PAL staging_area.shape_block > $dest_dir/tmp.sql
	
#less $dest_dir/tmp.sql

psql $extra_options--host=$db_host --port=$db_port --username=$db_user --dbname=$db_name --file=$dest_dir/tmp.sql
psql $extra_options --host=$db_host --port=$db_port --username=$db_user --dbname=$db_name --command="update staging_area.shape_block set section='$sectionnr', region='$region'
where section is null"

#rm $dest_dir/shptmp.sql
#added -g to specify the geom column PAL has the geom staging_area schem has geom column
#shp2pgsql -a -s   $srid  -g geom $dest_dir/$sectionnr/shape_lot/PAL staging_area.shape_lot > $dest_dir/shptmp.sql 
shp2pgsql -a -s $srid -g geom $dest_dir/$sectionnr/shape_lot/PAL staging_area.shape_lot > $dest_dir/shptmp.sql


#stage 4 run insert statements against  target database
#psql $extra_options--host=$db_host --port=$db_port --username=$db_user --dbname=$db_name --file=$dest_dir/shptmp.sql
psql $extra_options --host=$db_host --port=$db_port --username=$db_user --dbname=$db_name --file=$dest_dir/shptmp.sql --log-file=shit

