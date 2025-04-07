#!/bin/sh

. `dirname $0`/solr-env.sh

LATEST_BACKUP=$(aws s3 ls "s3://$BUCKET/solr_backup/$CORE_NAME/" |awk '{print $4}' |sort |tail -1)
if [ "$LATEST_BACKUP" = "" ]; then
    echo "Unable to find a backup Solr index in bucket $BUCKET"
    exit 1
fi

echo "Restoring from backup ${LATEST_BACKUP}..."
# Reset all servers to consume snapshots instead of generating them
for heartbeat_file in `ls /data/solr-healthcheck_*`; do
  touch $heartbeat_file.start
done
# Override regular snapshots with one from S3
sudo -u solr aws s3 cp "s3://$BUCKET/solr_backup/$CORE_NAME/$LATEST_BACKUP" $SYNC_DIR/override-snapshot.$CORE_NAME.tgz || exit 1
