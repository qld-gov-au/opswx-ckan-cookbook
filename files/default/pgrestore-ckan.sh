#!/bin/sh

set -x

NOW=$(date +%s)
BACKUP_DIR=/data/db_backups

import_database () {
  LATEST_BACKUP=$(ls -d $BACKUP_DIR/$PGDATABASE.*.dump.dir |tail -1)
  pg_restore -v -j 4 $LATEST_BACKUP --disable-triggers 2>&1 | tee -a $HOME/$PGDATABASE.$NOW.log
}

. `dirname $0`/psql-env-ckan.sh
echo "DBA account name:"
read -s PGUSER
export PGUSER
echo "DBA password:"
read -s PGPASSWORD
export PGPASSWORD

import_database

CKAN_PROPERTY="ckan.datastore.write_url"
if (grep "$CKAN_PROPERTY" /etc/ckan/default/production.ini); then
  export PGDATABASE="${PGDATABASE}_datastore"
  import_database
fi
