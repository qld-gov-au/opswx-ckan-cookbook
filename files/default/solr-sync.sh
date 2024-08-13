#!/bin/sh

set -x

. `dirname $0`/solr-env.sh

BACKUP_NAME="$CORE_NAME-$(date +'%Y-%m-%dT%H:%M')"
SNAPSHOT_NAME="snapshot.$BACKUP_NAME"
LOCAL_SNAPSHOT="$LOCAL_DIR/$SNAPSHOT_NAME"
SYNC_SNAPSHOT="$SYNC_DIR/${SNAPSHOT_NAME}.tgz"
MINUTE=$(date +%M)

function set_dns_primary () {
  if [ "$1" = "true" ]; then
    sed -i 's/^solr_slave=/solr_master=/' /etc/hostnames
  else
    sed -i 's/^solr_master=/solr_slave=/' /etc/hostnames
  fi
  updatedns &
}

function wait_for_replication_success () {
  # Wait for backup to complete.
  # Should only take a second or two for small indexes,
  # but larger ones can be slow.
  BACKUP_STATUS=unknown
  MAX_BACKUP_WAIT=120
  for i in $(eval echo "{1..$MAX_BACKUP_WAIT}"); do
    if [ "$BACKUP_STATUS" = "unknown" ]; then
      DETAILS=$(curl "$HOST/$CORE_NAME/replication?command=details")
      echo "Backup status on attempt $i: $DETAILS"
      if (echo "$DETAILS" |grep "$BACKUP_NAME"); then
        echo "$DETAILS" |grep 'status[^a-zA-Z]*success' && return 0
        echo "$DETAILS" |grep "exception.*$CORE_NAME" && return 1
      fi
      sleep 1
    fi
  done
  if [ "$BACKUP_STATUS" = "unknown" ]; then
    echo "Backup did not complete within $MAX_BACKUP_WAIT seconds"
    return 2
  fi
}

function export_snapshot () {
  # export a snapshot of the index and verify its integrity,
  # then copy to EFS so secondary servers can read it
  BACKUP_DETAILS=$(curl "$HOST/$CORE_NAME/replication?command=backup&location=$LOCAL_DIR&name=$BACKUP_NAME")
  echo "Backup status: $BACKUP_DETAILS"
  echo "$BACKUP_DETAILS" | grep 'status[^a-zA-Z]*OK' || return 1
  wait_for_replication_success; REPLICATION_STATUS=$?
  if [ "$REPLICATION_STATUS" != "0" ]; then
    return $REPLICATION_STATUS
  fi
  sh -c "$LUCENE_CHECK $LOCAL_SNAPSHOT && sudo -u solr tar --force-local --exclude=write.lock -czf $SYNC_SNAPSHOT -C $LOCAL_SNAPSHOT ." || return 1
}

function import_snapshot () {
  # Give the master time to update the sync copy
  for i in $(eval echo "{1..40}"); do
    if [ -f "$SYNC_SNAPSHOT" ]; then
      sudo service solr stop
      sudo -u solr mkdir $LOCAL_DIR/index
      rm -f $LOCAL_DIR/index/* && sudo -u solr tar -xzf "$SYNC_SNAPSHOT" -C $LOCAL_DIR/index || exit 1
      sudo systemctl start solr
      return 0
    else
      sleep 5
    fi
  done
  echo "Snapshot did not become available for import: $SYNC_SNAPSHOT"
  return 1
}

# we can't perform any replication operations if Solr is stopped
if ! (curl -I --connect-timeout 5 "$PING_URL" 2>/dev/null |grep '200 OK' > /dev/null); then
  set_dns_primary false
  exit 0
fi
sudo mkdir -p "$LOCAL_DIR"
sudo chown solr "$LOCAL_DIR"
if (/usr/local/bin/pick-solr-master.sh); then
  # point traffic to this instance
  set_dns_primary true

  # Export a snapshot of the index
  export_snapshot; EXPORT_STATUS=$?
  # Remove old snapshots
  for old_snapshot in $(ls -d $SYNC_DIR/snapshot.$CORE_NAME-* |grep -v "$SNAPSHOT_NAME"); do
    sudo -u solr rm -r "$old_snapshot"
  done
  # Drop this server from being master if export failed
  if [ "$EXPORT_STATUS" != "0" ]; then
    if [ "$EXPORT_STATUS" != "2" ]; then
      echo "Export failed; assume server is unhealthy"
      touch $HEARTBEAT_FILE.start
    fi
    exit 1
  fi

  # Hourly backup to S3
  if [ "$MINUTE" = "00" ]; then
    aws s3 cp "$SYNC_SNAPSHOT" "s3://$BUCKET/solr_backup/$CORE_NAME/" --expires $(date -d '30 days' --iso-8601=seconds)
  fi
else
  # make traffic come to this instance only as a backup option
  set_dns_primary false
  import_snapshot
fi
OLD_SNAPSHOTS=$(ls -d $LOCAL_DIR/snapshot.$CORE_NAME-* |grep -v "$SNAPSHOT_NAME")
if [ "$OLD_SNAPSHOTS" != "" ]; then
    sudo -u solr rm -r $OLD_SNAPSHOTS
fi
