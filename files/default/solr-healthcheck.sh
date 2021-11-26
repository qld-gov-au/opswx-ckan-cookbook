#!/bin/sh

# ensure we can still grab the correct exit code after piping output to 'tee'
set +o pipefail

. `dirname $0`/solr-env.sh

MAX_AGE=120

LOG_FILE="/var/log/solr/solr_${CORE_NAME}_health-check.log"
BACKUP_DIR="/tmp/snapshot.health_check"

fix_index () {
  # Attempt to fix a corrupted Lucene index.
  # This will drop the server out of the pool,
  # as the Lucene check can only run offline.
  rm $HEARTBEAT_FILE
  sudo service solr stop
  # extract the index location from 'index.properties' if it exists,
  # otherwise default to 'index'
  INDEX_DIR=$(grep 'index=' "$DATA_DIR/index.properties" |awk -F= '{print $2}')
  if [ "$INDEX_DIR" = "" ]; then
    INDEX_DIR=index
  fi
  INDEX_DIR="$DATA_DIR/$INDEX_DIR"
  # Attempt to exorcise index corruption.
  # If even that fails, move the whole index aside for later forensics
  # and copy a fresh index from the EFS sync.
  if ! (sudo -u solr sh -c "$LUCENE_CHECK $INDEX_DIR >> $LOG_FILE"); then
    # Lucene returns an error code if the index was bad,
    # even if it was successfully exorcised,
    # so check again to determine whether we actually succeeded.
    sudo -u solr sh -c "(echo 'Index failed check, attempting to fix'; \
        $LUCENE_CHECK -exorcise $INDEX_DIR; $LUCENE_CHECK $INDEX_DIR || \
            (echo 'Index is unrecoverable, copy from backup'; \
            mv $INDEX_DIR $INDEX_DIR.bad.`date +'%s'` && \
            rm $DATA_DIR/index.properties && \
            rsync -a --delete $SYNC_DIR/index/ $DATA_DIR/index') \
        ) >> $LOG_FILE"
  fi
  sudo service solr start
  touch $HEARTBEAT_FILE
}

is_ping_healthy () {
  (curl -I "$PING_URL" 2>/dev/null |grep '200 OK' > /dev/null) || return 1
}

is_index_healthy () {
  curl "$HOST/$CORE_NAME/replication?command=backup&location=/tmp&name=health_check" 2>/dev/null \
    |grep '"status": *"OK"' > /dev/null
  IS_HEALTHY=$?
  if [ "$IS_HEALTHY" = "0" ]; then
    sudo -u solr sh -c "$LUCENE_CHECK $BACKUP_DIR >> $LOG_FILE"
    IS_HEALTHY=$?
  fi
  if [ "$IS_HEALTHY" -ne "0" ]; then
    fix_index
  fi
  rm -rf "$BACKUP_DIR"
  # even if fix_index worked, don't become master yet,
  # because we might have cleared the index and need to resync.
  return $IS_HEALTHY
}

is_healthy () {
  is_ping_healthy || return 1
  is_index_healthy || return 1
}

# Only update heartbeat if it is present.
# This allows us to manually drop a server from the pool
if ! [ -e "$HEARTBEAT_FILE" ]; then
  exit 0
fi

CURRENT_TIME=$(date +%s)
is_healthy || exit 1
PREVIOUS_HEALTH_TIME=$(cat $HEARTBEAT_FILE | tr -d '[:space:]')
echo $CURRENT_TIME > "$HEARTBEAT_FILE"
if [ "$PREVIOUS_HEALTH_TIME" = "" ]; then
  IS_HEALTHY=1
else
  AGE=$(expr $CURRENT_TIME - $PREVIOUS_HEALTH_TIME)
  IS_HEALTHY=$(expr $AGE '>' $MAX_AGE)
fi
if [ "$IS_HEALTHY" = "0" ]; then
  rm -f $STARTUP_FILE
else
  touch $STARTUP_FILE
fi
