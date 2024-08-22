#!/bin/sh

# Identify whether the current server is the Solr master.

. `dirname $0`/solr-env.sh

# Look for a special file that marks the server as secondary
# until it has imported an index
if [ -e "$STARTUP_FILE" ]; then return 1; fi

function is_healthy() {
  HEALTH_FILE=$1
  IGNORE_STARTUP=$2
  if [ ! -e "$HEALTH_FILE" ]; then
    return 1
  fi
  if [ -e "$HEALTH_FILE.start" ]; then
    return 1
  fi
  HEALTH_TIME=$(cat $1 | tr -d '[:space:]')
  if [ "$HEALTH_TIME" = "" ]; then
    return 1
  fi
  AGE=$(expr $NOW - $HEALTH_TIME)
  return $(expr $AGE '>' $MAX_AGE)
}

NOW=$(date +'%s')
MAX_AGE=120

HEALTH_CHECK_PREFIX=/data/solr-healthcheck_
HEALTH_CHECK_FILES=$(ls -r ${HEALTH_CHECK_PREFIX}* || echo '')
for health_check_file in $HEALTH_CHECK_FILES; do
  if is_healthy "$health_check_file"; then
    SELECTED_SERVER="$health_check_file"
  fi
done
exit $([ "$SELECTED_SERVER" = "${HEALTH_CHECK_PREFIX}$opsworks_hostname" ])
