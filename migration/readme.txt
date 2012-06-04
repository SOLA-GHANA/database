1. Script convert-all.bat
What does this script do?
* It empties the staging area in the target database.
* It searches for files of format S*.zip in folder data\source.
* For each file that is found there, it calls the script convert-single.bat.
Configuration of script:
 - db_host: is the server where the database is found
 - db_port: is the port where the database runs
 - db_name: the database name
 - region: The abbreviation code of the region for which the data is
Note:The database password is not given because in Windows, if you are logged in once with the database 
using pgAdmin, the password is stored locally.

2. Script convert-single.bat
What does the script do?
* Removes folder in destination that will be used for temporary data
* Extracts the archive to the destination folder
* Converts LOT Data from ArcInfo format to ArcInfo Coverage
* Converts BLOCK Data from ArcInfo format to ArcInfo Coverage
* Converts LOT Data from ArcInfo Coverage to Shapefile
* Converts BLOCK Data from ArcInfo Coverage to Shapefile
* Converts BLOCK Shapefile to .sql file with insert statements (only PAL.shp)
* Runs the .sql script against the database and populate the table staging_area.shape_block
* Updates the new inserted records to accept the section identifier and the region
* Converts LOT Shapefile to .sql file with insert statements (only PAL.shp)
* Runs the .sql script against the database and populate the table staging_area.shape_lot

It takes parameters in this order:
- sectionnr: This is of format S020. So not only the section number, but it is with an S before.
- db_host: is the server where the database is found
- db_port: is the port where the database runs
- db_name: the database name
- region: The abbreviation code of the region for which the data is

This script is called by convert-all.bat.
