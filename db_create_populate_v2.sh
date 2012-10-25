#!/bin/bash
clear
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

psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -f "sola.sql"
psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -f "business_rules.sql"
psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -f "br_generators.sql"
psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -f "br_target_cadastre_object.sql"
psql -U $DBUSER -h $DBHOSTNAME -p $DBPORT -d $DBNAME -f "br_target_application_action.sql"
