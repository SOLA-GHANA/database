#!/bin/bash
host="localhost"
#host="exlprcadreg3.ext.fao.org"
script_folder="./"
dbname="sola"
nopass=""
#psql --host=$host --port=5432 --username=postgres $nopass --dbname=$dbname --command="create database "$dbname" with encoding='UTF8' template=template_postgis connection limit=-1;"
psql --host=$host --port=5432 --username=postgres $nopass --dbname=$dbname --file=$script_folder"sola.sql"
psql --host=$host --port=5432 --username=postgres $nopass --dbname=$dbname --file=$script_folder"test_data.sql"
psql --host=$host --port=5432 --username=postgres $nopass --dbname=$dbname --file=$script_folder"business_rules.sql"
psql --host=$host --port=5432 --username=postgres $nopass --dbname=$dbname --file=$script_folder"migration/db-scripts/migrate-spatial.sql"

