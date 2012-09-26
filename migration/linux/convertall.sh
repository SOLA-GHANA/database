#!/bin/bash
src_dir=$1
dest_dir=$2
region=GA

#loops through source and destination files and executed convertsingle.sh
#errors are appeneded to logs file

for file in $( ls $src_dir )
do
 if [ "${file##*.}"="ZIP" ]
 then 
   echo  `date` >> logs
   echo "${file%.*}" >> logs
   ./migratedistrict.sh  "${file%.*}"  localhost  5433 sola postgres  $region $src_dir $dest_dir 2>> logs 
 else
	echo "files in source directory must end with .ZIP"
	echo error in processing $file >> logs
	exit 1
 fi 
done
