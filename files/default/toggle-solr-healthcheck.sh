#!/bin/sh

. `dirname $0`/solr-env.sh

usage () {
  echo "Usage: $0 on|off"
  exit 1
}
if [ "$#" -lt 1 ]; then
  usage
fi
COMMAND="$1"
if [ "$COMMAND" = "on" ]; then
  sudo touch $HEARTBEAT_FILE
elif [ "$COMMAND" = "off" ]; then
  sudo rm -f $HEARTBEAT_FILE
else
  usage
fi
