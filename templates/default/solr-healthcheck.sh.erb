#!/bin/sh

HEARTBEAT_FILE="/data/solr-healthcheck_<%= node['datashades']['hostname'] %>"
# Only update heartbeat if it is present.
# This allows us to manually drop a server from the pool
if [ -e "$HEARTBEAT_FILE" ]; then
  CURRENT_TIME=`date +%s`
  if (curl -I "http://localhost:8983/solr/<%= node['datashades']['app_id'] %>-<%= node['datashades']['version'] %>/admin/ping" 2>/dev/null |grep '200 OK' > /dev/null); then
    echo $CURRENT_TIME > "$HEARTBEAT_FILE"
  else
    exit 1
  fi
fi
