#!/bin/sh

set -x

NOW=$(date +%s)
BACKUP_DIR=/data/db_backups
sudo mkdir $BACKUP_DIR
sudo chown `whoami` $BACKUP_DIR

export_database () {
  pg_dump -v -F d -f $BACKUP_DIR/$PGDATABASE.$NOW.dump.dir -j 4 --disable-triggers 2>&1 | tee -a $HOME/$PGDATABASE.$NOW.log
}

. `dirname $0`/psql-env-ckan.sh
echo "DBA account name:"
read -s PGUSER
export PGUSER
echo "DBA password:"
read -s PGPASSWORD
export PGPASSWORD

export_database

CKAN_PROPERTY="ckan.datastore.write_url"
if (grep "$CKAN_PROPERTY" /etc/ckan/default/production.ini); then
  export PGDATABASE="${PGDATABASE}_datastore"
  export_database
fi
