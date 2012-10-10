To run the script:
------------------
1. Ensure the avce00 and gdal-bin libraries are installed executing machine
   #aptitude install avce00 gdal-bin

2. Ensure run.sh file has execute privilege 
   $chmod 755 run.sh

3. Place the section source files (zip) into:
   data/source/section

4. Place the district source files (zip) into:
   data/source/district

5. Run the script
   $./run.sh


File Structure Description
--------------------------

FOLDERS:
--------
data/source/section = Location for section source files.
data/source/district = Location for district source files.
data/destination = Location where temporary files are created. Anything placed here will be DELETED when the script completes.
logs = Location for various source files
sql = Location where various sql scripts are invoked by the program



FILES:
------
run.sh = Primary file invoked to migrate data into SOLA database
logs/cadastre_migration.log = Logs of moving data from staging_area into respective cadastre schema objects
logs/connectivity.log = Logs of database connectivity test
logs/districts.log = Logs of migrating district data
logs/sections.log = Logs of migrating section data
logs/staging_area = Logs of creating staging_area 
sql/staging_area = SQL statements that creates staging_area schema and its objects with some pre-defined data.
sql/migrate_cadastre = SQL statements that migrates data from staging_area objects into respective cadastre objects.







   

