#!/bin/sh

# This script retrieves the latest backed-up Solr index from S3,
# and applies it to the current Solr instance.
# This will cause a brief outage, as Solr will be stopped
# and its index overwritten with the snapshot.

if [ "$(whoami)" != "root" ]; then
    echo "$0 must be run as root"
    exit 1
fi

if ! (grep 'solr_master' /etc/hostnames); then
    echo "WARNING: This server is not the master instance, restored index may not take effect!"
fi

. `dirname $0`/solr-env.sh

LATEST_BACKUP=$(aws s3 ls "s3://$BUCKET/solr_backup/$CORE_NAME/" |awk '{print $4}' |sort |tail -1)
if [ "$LATEST_BACKUP" = "" ]; then
    echo "Unable to find a backup Solr index in bucket $BUCKET"
    exit 1
fi

# Retrieve snapshot from S3
sudo -u solr aws s3 cp "s3://$BUCKET/solr_backup/$CORE_NAME/$LATEST_BACKUP" $LOCAL_DIR/override-snapshot.$CORE_NAME.tgz || exit 1

# Import index into current server
sh `dirname $0`/solr-import-backup.sh $LOCAL_DIR/override-snapshot.$CORE_NAME.tgz
