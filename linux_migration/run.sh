#!/bin/bash
clear
echo 
echo "****************************************"
echo "Welcome to the SOLA Ghana data migration"
echo "****************************************"
echo 
echo "This program has been developed for Ubuntu Linux"
echo
echo "Database Connectivity"
echo "....................."

#Accepting Database connection parameters.
read -p "Server IP Address / Host name [localhost]:" DBHOSTNAME
read -p "Server Port [5432]:" DBPORT
read -p "Database name [sola]:" DBNAME
read -p "Database User [postgres]:" DBUSER
read -s -p "Database User Password:" DBPWD

#Ensure that the database password value for the supplied user is provided
if [[ -z "$DBPWD" ]]; then
     echo ""
     echo "ERROR: Database password must be provided"
     exit 1;
else
	export PGPASSWORD=$DBPWD
fi

#if no values were supplied for some database connection parameters, assign default values
if [[ -z "$DBHOSTNAME" ]]; then
	DBHOSTNAME="localhost"
fi
if [[ -z "$DBPORT" ]]; then
	DBPORT="5432"
fi
if [[ -z "$DBNAME" ]]; then
	DBNAME="sola"
fi
if [[ -z "$DBUSER" ]]; then
	DBUSER="postgres"
fi

#Test database connection parameters.
echo 
echo 
echo "Checking Database Connectivity:"
psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME --command="SELECT now(),'Database Connection OK' as \"Database\"" -t &> logs/connectivity.log
RSLT=`cat logs/connectivity.log`
if [[ "$RSLT" =~ "Connection OK" ]] 
then 
	echo "Database connection ... OK"
else
	echo "Database connection ... FAILED"
	echo "See "`pwd`"/logs/connectivity.log"
	unset PGPASSWORD
	exit 1
fi

#Preparing staging_area where section and district source file (IN RAW ZIP FILES) will be 
#initially uploaded into the database before being subsequently transfered into their final 
#destination 

echo 
echo "Preparing Staging Area:"
#Constructing staging_area Schema from the "staging_area.sql" script located in the "sql" folder
psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -f "sql/staging_area.sql" &> logs/staging_area.log

#Checking for possible errors during creation of staging_area
RSLT=`cat logs/staging_area.log`
if [[ "$RSLT" =~ "ERROR:" ]] 
then 
	echo "Staging Area ... FAILED"
	echo "See "`pwd`"/logs/staging_area.log"
	unset PGPASSWORD
	exit 1
else
	echo "Staging Area ... OK"
fi
echo

#Get a different SRID just in case the default is not suitable
read -p "SRID [2136]: " SRID
if [[ -z "$SRID" ]]; then
	SRID="2136"
fi

#************************
#MIGRATING DISTRICT DATA* 
#************************
echo ""
#Check with user if he/she will like to migrate district data
EXIT_LOOP=0
while [[ $EXIT_LOOP -eq 0 ]]
do
  read -p "Will you be migrating District Data? (Y/N)" ANSDIST
  case $ANSDIST in
    y|Y|Yes|yes|YES|n|N|No|no|NO)
      EXIT_LOOP=1
      ;;
    *)
      echo ""
      echo Invalid choice. Enter Yes or No
      EXIT_LOOP=0
      ;;
  esac 
done
echo

if [[ "$ANSDIST" =~ "Y" || "$ANSDIST" =~ "y" ]] 
then 
	#User has agreed to migrate district data so confirm default or get location of district source files
	read -p "Location of District Source files ["`pwd`"/data/source/districts]:" DISTSRCDIR
	if [[ -z "$DISTSRCDIR" ]]; then
		DISTSRCDIR=`pwd`"/data/source/districts"
	fi

	#Create a temporary folder extracted district source files
	DISTDESTDIR=`pwd`"/data/destination/districts"

	#Clear pre-existing (if any) district data from previous operations
	rm -rf $DISTDESTDIR &> logs/districts.log
	mkdir -p $DISTDESTDIR &> logs/districts.log

	#Take each ZIP file in the specified district source location and process it.
	for FILE in $( ls $DISTSRCDIR)
	do
	   echo "Processing District File ... "$FILE
	   #Get the district number from the name of the selected ZIP file.
	   #DISTNO="${FILE%.*}"

	   #Create a folder for the selected district ZIP file and extract the selected file
	   rm -rf $DISTDESTDIR/$FILE &> logs/districts.log
	   cp -r $DISTSRCDIR/$FILE $DISTDESTDIR/$FILE &>> logs/districts.log

	   #Unzip the selected district file into the specified location.
	   #unzip  $DISTSRCDIR/$FILE  -d $DISTDESTDIR &>> logs/districts.log

	   #it is expected that the unzipped file has a ".shp" file which must be selected and processed
	   SHPFILE=`ls $DISTDESTDIR/$FILE|grep -i .shp$`
	
	   #converting the .shp file into sql insert statements and storing it in the "district_data.sql" file
	   shp2pgsql -a -s $SRID -g the_geom $DISTDESTDIR/$FILE/$SHPFILE staging_area.district|grep -i INSERT &> "$DISTDESTDIR/$FILE/district_data.sql"
	
	   #Run the "district_data.sql" against the postgres database to insert data into the staging_area.district table
	   psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -f "$DISTDESTDIR/$FILE/district_data.sql" &>> logs/districts.log
	   echo ""
	done
fi 




#********************
#WORKING ON SECTION* 
#********************

#Check with user if he/she will like to migrate section data

EXIT_LOOP=0
while [[ $EXIT_LOOP -eq 0 ]]
do
  read -p "Will you be migrating Section Data (Y/N)" ANSSEC
  case $ANSSEC in
    y|Y|Yes|yes|YES|n|N|No|no|NO)
      EXIT_LOOP=1
      ;;
    *)
      echo ""
      echo Invalid choice. Enter Yes or No
      EXIT_LOOP=0
      ;;
  esac 
done
echo
if [[ "$ANSSEC" =~ "Y" || "$ANSSEC" =~ "y" ]] 
then 
	#User has agreed to migrate section data so confirm default or get location of section source files
	read -p "Location of Section Source files ["`pwd`"/data/source/sections]:" SECSRCDIR
	if [[ -z "$SECSRCDIR" ]]; then
		SECSRCDIR=`pwd`"/data/source/sections"
	fi

	#Create a temporary folder for extracted section source files
	SECDESTDIR=`pwd`"/data/destination/sections"

	echo ""
	EXIT_LOOP=0
	while [[ $EXIT_LOOP -eq 0 ]]
	do
	  echo "Select a Region for migrating all section data"
	  echo "1. Greater Accra"
	  echo "2. Ashanti"
	  echo "3. Brong Ahafo"
	  echo "4. Central"
	  echo "5. Eastern"
	  echo "6. Northern"
	  echo "7. Volta"
	  echo "8. Upper East"
	  echo "9. Upper West"
	  echo "10. Western"
	  read -p "Enter Choice [1-10] " ANSREG
	  case $ANSREG in
	    1)
	      ANSREG='GA'
	      EXIT_LOOP=1
	      ;;
	    2)
	      ANSREG='AS'
	      EXIT_LOOP=1
	      ;;
	    3)
	      ANSREG='BA'
	      EXIT_LOOP=1
	      ;;
	    4)
	      ANSREG='CR'
	      EXIT_LOOP=1
	      ;;
	    5)
	      ANSREG='ER'
	      EXIT_LOOP=1
	      ;;
	    6)
	      ANSREG='NR'
	      EXIT_LOOP=1
	      ;;
	    7)
	      ANSREG='VR'
	      EXIT_LOOP=1
	      ;;
	    8)
	      ANSREG='UE'
	      EXIT_LOOP=1
	      ;;
	    9)
	      ANSREG='UW'
	      EXIT_LOOP=1
	      ;;
	    10)
	      ANSREG='WR'
	      EXIT_LOOP=1
	      ;;
	    *)
	      echo ""
	      echo Invalid choice.
	      EXIT_LOOP=0
	      ;;
	  esac 
	done
	echo
else
	echo "Nothing more to do. Program terminated."
	unset PGPASSWORD
        exit 1
fi 


#Take each ZIP file in the specified section source location and process it.
for FILE in $( ls $SECSRCDIR)
do
   echo "Processing Sections File ... "$FILE
   
   #Get the district number from the name of the selected ZIP file.	
   #FILE="${FULLFILENAME%.*}"
   SECNO=${FILE:4:4}
   DISTNO=${FILE:0:4}
   echo "District: "$DISTNO" Section: "$SECNO
   

   #Create a folder for the selected section ZIP file and extract the selected file
   rm -rf $SECDESTDIR/$FILE &>> logs/sections.log
   mkdir -p $SECDESTDIR/$FILE &>> logs/sections.log

   #Copy to the destination folder.
   cp -r $SECSRCDIR/$FILE $SECDESTDIR


   ######### Move block shape file #################################################################

   #Delete staging_area.t table if present
   psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -c "drop table if exists staging_area.t" &>> logs/sections.log

   #Converts BLOCK Shapefile to block_data.sql file with create table and insert statements
   shp2pgsql -s $SRID -g geom $SECDESTDIR/$FILE/BLOCK staging_area.t >  "$SECDESTDIR/$FILE/block_data.sql"
     
   #Runs the block_data.sql script against the database and populate the table staging_area.t
   psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -f "$SECDESTDIR/$FILE/block_data.sql" &>> logs/sections.log

   #Move rows from staging_area.t to stagign_area.shape_block 
   psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -c "insert into staging_area.shape_block(region, district, section, blockno, geom) select '$ANSREG', '$DISTNO', '$SECNO', blockno, geom from staging_area.t" &>> logs/sections.log

   ######### Move lot shape file ###################################################################

   #Delete staging_area.t table if present
   psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -c "drop table if exists staging_area.t" &>> logs/sections.log

   #Converts LOT Shapefile to lot_data.sql file with create table and insert statements
   shp2pgsql -s $SRID -g geom $SECDESTDIR/$FILE/LOT staging_area.t >"$SECDESTDIR/$FILE/lot_data.sql"

   #Runs the lot_data.sql script against the database and populate the table staging_area.shape_lot
   psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -f "$SECDESTDIR/$FILE/lot_data.sql" &>> logs/sections.log

   #Move rows from staging_area.t to stagign_area.shape_lot 
   psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -c "insert into staging_area.shape_lot(lotno, geom) select lotno, geom from staging_area.t" &>> logs/sections.log

   #Delete staging_area.t table if present
   psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -c "drop table if exists staging_area.t" &>> logs/sections.log

   echo ""
done

#if the user chose to migrate either district or section data, then invoke migrate_cadastre.sql script 
#which will move data from the staging area into their respective cadatastre schema objects
if [[ "$ANSSEC" =~ "Y" || "$ANSSEC" =~ "y" ]] || [[ "$ANSDIST" =~ "Y" || "$ANSDIST" =~ "y" ]]; then
	echo "Processing data from Staging Area into Cadastre Schema ..."
	psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -f "sql/migrate_cadastre.sql" &> logs/cadastre_migration.log
fi

#Clean-UP
echo 
echo "Cleaning up..."
rm -rf $SECDESTDIR
rm -rf $DISTDESTDIR
unset PGPASSWORD

echo
echo "Migration ended. See log for detailed results."
