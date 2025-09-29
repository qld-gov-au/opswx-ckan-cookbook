#!/bin/sh

# ensure we can still grab the correct exit code after piping output to 'tee'
set +o pipefail

. `dirname $0`/solr-env.sh

# Only update heartbeat if it is present.
# This allows us to manually drop a server from the pool
if ! [ -e "$HEARTBEAT_FILE" ]; then
  exit 0
fi

function set_dns_primary () {
  if [ "$1" = "true" ]; then
    sed -i 's/^solr_slave=/solr_master=/' /etc/hostnames
  else
    sed -i 's/^solr_master=/solr_slave=/' /etc/hostnames
  fi
  updatedns &
}

is_ping_healthy () {
  (curl -I --connect-timeout 5 "$PING_URL" 2>/dev/null |grep '200 OK' > /dev/null) || return 1
}

MAX_AGE=120
CURRENT_TIME=$(date +%s)
is_ping_healthy || exit 1
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

if (/usr/local/bin/pick-solr-master.sh); then
  set_dns_primary true
else
  set_dns_primary false
fi
