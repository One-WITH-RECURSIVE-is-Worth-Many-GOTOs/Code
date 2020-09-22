#!/bin/bash

PORT=${1:- -p 5432}
SF=${2:-s001}

echo "Create Tables and indexes"

psql $PORT -f dss.ddl

for i in `ls $SF/*.tbl`
do
    echo $i
    name=`echo $i|cut -d'.' -f1|cut -d '/' -f2`
    psql $PORT -c "COPY $name FROM '`pwd`/$i' DELIMITER '|' ENCODING 'LATIN1';"
done


psql $PORT -f dss_primary_keys.ddl
psql $PORT -f dss_foreign_keys.ddl
psql $PORT -f dss_indexes.ddl

psql $PORT -c "VACUUM ANALYZE;"

