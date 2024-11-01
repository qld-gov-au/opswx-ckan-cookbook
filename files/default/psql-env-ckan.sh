#!/bin/sh

if [ "$CKAN_PROPERTY" = "" ]; then
  CKAN_PROPERTY="sqlalchemy[.]url"
fi
CONNECTION_STRING=$(grep "$CKAN_PROPERTY" /etc/ckan/default/production.ini |awk -F '//' '{print $2}')
export PGUSER=$(echo "$CONNECTION_STRING" | awk -F ':' '{print $1}')
CONNECTION_STRING=$(echo "$CONNECTION_STRING" | awk -F ':' '{print $2}')
export PGPASSWORD=$(echo "$CONNECTION_STRING" | awk -F '@' '{print $1}')
CONNECTION_STRING=$(echo "$CONNECTION_STRING" | awk -F '@' '{print $2}')
export PGHOST=$(echo "$CONNECTION_STRING" | awk -F '/' '{print $1}')
export PGDATABASE=$(echo "$CONNECTION_STRING" | awk -F '/' '{print $2}')
