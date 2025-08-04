#!/bin/sh

if [ "$(id -ru)" != "0" ]; then
    echo "$0 must be run as root"
    exit 1
fi

. `dirname $0`/solr-env.sh

LATEST_BACKUP=$(aws s3 ls "s3://$BUCKET/solr_backup/$CORE_NAME/" |awk '{print $4}' |sort |tail -1)
if [ "$LATEST_BACKUP" = "" ]; then
    echo "Unable to find a backup Solr index in bucket $BUCKET"
    exit 1
fi

echo "Restoring from backup ${LATEST_BACKUP}..."
# Disable all servers
for heartbeat_file in `ls /data/solr-healthcheck_*`; do
  echo "" > $heartbeat_file
  mv $heartbeat_file /tmp/
done

# Override regular snapshots with one from S3
sudo -u solr aws s3 cp "s3://$BUCKET/solr_backup/$CORE_NAME/$LATEST_BACKUP" $SYNC_DIR/override-snapshot.$CORE_NAME.tgz || exit 1

# Import index into current server
sh `dirname $0`/solr-import-backup.sh $SYNC_DIR/override-snapshot.$CORE_NAME.tgz

# Make this server the master
mv /tmp/solr-healthcheck_${opsworks_hostname} /data/

# Wait for Solr to start
for i in $(eval echo "{1..6}"); do
    curl -I --connect-timeout 5 "$PING_URL" 2>/dev/null |grep '200 OK' && break
    sleep 5
done
sh `dirname $0`/solr-healthcheck.sh
sh `dirname $0`/solr-sync.sh

# Allow other servers, if any, to re-enter the pool
if (ls /tmp/ | grep 'solr-healthcheck_'); then
    mv /tmp/solr-healthcheck_* /data/;
fi
