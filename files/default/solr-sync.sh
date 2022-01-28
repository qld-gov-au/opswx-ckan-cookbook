#!/bin/sh

. `dirname $0`/solr-env.sh

BACKUP_NAME="$CORE_NAME-$(date +'%Y-%m-%dT%H:%M')"
SNAPSHOT_NAME="snapshot.$BACKUP_NAME"
LOCAL_SNAPSHOT="$LOCAL_DIR/$SNAPSHOT_NAME/"
SYNC_SNAPSHOT="$SYNC_DIR/$SNAPSHOT_NAME/"
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
  # wait up to 20 seconds for backup to complete, should only take a second or two
  BACKUP_STATUS=unknown
  for i in {1..20}; do
    if [ "$BACKUP_STATUS" = "unknown" ]; then
      DETAILS=$(curl "$HOST/$CORE_NAME/replication?command=details")
      echo "$DETAILS" |grep 'status[^a-zA-Z]*success' && return 0
      echo "$DETAILS" |grep 'exception.*snapshot' && return 1
      sleep 1
    fi
  done
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

  # export a snapshot of the index and verify its integrity,
  # then copy to EFS so secondary servers can read it
  curl "$HOST/$CORE_NAME/replication?command=backup&location=$LOCAL_DIR&name=$BACKUP_NAME" | grep 'status[^a-zA-Z]*OK' || exit 1
  wait_for_replication_success || exit 1
  sudo -u solr sh -c "$LUCENE_CHECK $LOCAL_SNAPSHOT && rsync -a --delete '$LOCAL_SNAPSHOT' '$SYNC_SNAPSHOT'" || exit 1

  # clean up - remove old snapshots, hourly backup to S3
  for old_snapshot in $(ls -d $SYNC_DIR/snapshot.$CORE_NAME-* |grep -v "$SNAPSHOT_NAME"); do
    sudo -u solr rm -r "$old_snapshot"
  done
  if [ "$MINUTE" = "00" ]; then
    cd "$LOCAL_DIR"
    tar --force-local -czf "$SNAPSHOT_NAME.tgz" "$SNAPSHOT_NAME"
    aws s3 mv "$SNAPSHOT_NAME.tgz" "s3://$BUCKET/solr_backup/$CORE_NAME/" --expires $(date -d '30 days' --iso-8601=seconds)
    sudo -u solr rm -r snapshot.$CORE_NAME-*
  fi
else
  # make traffic come to this instance only as a backup option
  set_dns_primary false
  # Give the master time to update the sync copy; run halfway between exports
  sleep 30
  if [ -d "$SYNC_SNAPSHOT" ]; then
    sudo -u solr rm -r $LOCAL_DIR/snapshot.$CORE_NAME-*
    sudo -u solr rsync -a --delete "$SYNC_SNAPSHOT" "$LOCAL_SNAPSHOT" || exit 1
    curl "$HOST/$CORE_NAME/replication?command=restore&location=$LOCAL_DIR&name=$BACKUP_NAME"
  fi
fi
