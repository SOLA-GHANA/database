@echo off
set sectionnr=%1
set db_host=%2
set db_port=%3
set db_name=%4
set db_user=%5
set region=%6
set srid=2136
set extra_options=--quiet -v ON_ERROR_STOP=1 
rd /s /q data\dest\%sectionnr%
7z -y x data\source\%sectionnr%.ZIP -odata\dest\%sectionnr%
avcimport data\dest\%sectionnr%\LOT.E00 data\dest\%sectionnr%\cov_lot
avcimport data\dest\%sectionnr%\BLOCK.E00 data\dest\%sectionnr%\cov_block
ogr2ogr -f "ESRI Shapefile" -skipfailures -overwrite data\dest\%sectionnr%\shape_lot data\dest\%sectionnr%\cov_lot
ogr2ogr -f "ESRI Shapefile" -skipfailures -overwrite data\dest\%sectionnr%\shape_block data\dest\%sectionnr%\cov_block
psql\shp2pgsql -a -s %srid% data\dest\%sectionnr%\shape_block\PAL testdata.shape_block > data\dest\tmp.sql
psql\psql %extra_options% --host=%db_host% --port=%db_port% --username=%db_user% --dbname=%db_name% --file=data\dest\tmp.sql
psql\psql %extra_options% --host=%db_host% --port=%db_port% --username=%db_user% --dbname=%db_name% --command="update testdata.shape_block set section='%sectionnr%', region='%region%' where section is null"
psql\shp2pgsql -a -s %srid% data\dest\%sectionnr%\shape_lot\PAL testdata.shape_lot > data\dest\tmp.sql
psql\psql %extra_options% --host=%db_host% --port=%db_port% --username=%db_user% --dbname=%db_name% --file=data\dest\tmp.sql
