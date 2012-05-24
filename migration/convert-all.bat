@echo off
set db_host=ubtserver
set db_port=5432
set db_name=sola_ghana
set db_user=postgres
set region=GA
set extra_options=--quiet -v ON_ERROR_STOP=1 
psql\psql %extra_options% --host=%db_host% --port=%db_port% --username=%db_user% --dbname=%db_name% --command="delete from testdata.shape_block"
psql\psql %extra_options% --host=%db_host% --port=%db_port% --username=%db_user% --dbname=%db_name% --command="delete from testdata.shape_lot"
for /f %%i in ('dir /b data\source\S*.zip') do call convert-single.bat %%~ni %db_host% %db_port% %db_name% %db_user% %region%
