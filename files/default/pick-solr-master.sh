#!/bin/sh

# Identify whether the current server is the Solr master.

. `dirname $0`/solr-env.sh

function is_healthy() {
  HEALTH_FILE=$1
  IGNORE_STARTUP=$2
  if [ ! -e "$HEALTH_FILE" ]; then
    HEALTHY=1
  else
    HEALTH_TIME=$(cat $1 | tr -d '[:space:]')
    if [ "$HEALTH_TIME" = "" ]; then
      HEALTHY=1
    else
      AGE=$(expr $NOW - $HEALTH_TIME)
      HEALTHY=$(expr $AGE '>' $MAX_AGE)
    fi
    # clean up redundant "secondary" markers on servers that aren't active
    if [ "$HEALTHY" = "0" ]; then
      if [ -e "$HEALTH_FILE.start" ]; then
        HEALTHY=1
      fi
    else
      rm -f $HEALTH_FILE.start
    fi
  fi
  return $HEALTHY
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
