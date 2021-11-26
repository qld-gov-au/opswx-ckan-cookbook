#!/bin/sh

# Identify whether the current server is the Solr master.

. `dirname $0`/solr-env.sh

function is_healthy() {
  HEALTH_FILE=$1
  IGNORE_STARTUP=$2
  if [ ! -e "$HEALTH_FILE" ]; then
    return 1
  fi
  if [ -e "$HEALTH_FILE.start" ] && [ "$IGNORE_STARTUP" != "true" ]; then
    return 1
  fi
  HEALTH_TIME=$(cat $1 | tr -d '[:space:]')
  if [ "$HEALTH_TIME" = "" ]; then
    return 1
  fi
  AGE=$(expr $NOW - $HEALTH_TIME)
  return $(expr $AGE '>' $MAX_AGE)
}

layer_prefix=$(echo "$opsworks_hostname" | tr -d '[0-9]')
NOW=$(date +'%s')
MAX_AGE=120
for i in {9..1}; do
  SERVER_NAME="$layer_prefix$i"
  if is_healthy "/data/solr-healthcheck_$SERVER_NAME"; then
    SELECTED_SERVER="$SERVER_NAME"
  fi
done
# if we have no master, try grabbing one that's only passed a single health check
if [ "$SELECTED_SERVER" = "" ]; then
  for i in {9..1}; do
    SERVER_NAME="$layer_prefix$i"
    if is_healthy "/data/solr-healthcheck_$SERVER_NAME" true; then
      SELECTED_SERVER="$SERVER_NAME"
    fi
  done
fi
exit $([ "$SELECTED_SERVER" = "$opsworks_hostname" ])
