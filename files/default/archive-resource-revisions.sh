#!/bin/sh

DB_URL=$(grep 'sqlalchemy\.url' /etc/ckan/default/production.ini |awk -F '://' '{print $2}')
export PGUSER=$(echo "$DB_URL" |awk -F: '{print $1}')
DB_URL=$(echo "$DB_URL" |awk -F: '{print $2}')
export PGPASSWORD=$(echo "$DB_URL" |awk -F@ '{print $1}')
DB_URL=$(echo "$DB_URL" |awk -F@ '{print $2}')
export PGHOST=$(echo "$DB_URL" |awk -F/ '{print $1}')
export PGDATABASE=$(echo "$DB_URL" |awk -F/ '{print $2}')

psql -f $(dirname $0)/create-resource-revision-archival-table.sql || echo "Archival table already exists or could not be created"
psql -1f $(dirname $0)/archive-resource-revisions.sql
