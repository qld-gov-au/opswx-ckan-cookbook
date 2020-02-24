#!/bin/sh

QUEUE=$(/usr/lib/ckan/default/bin/paster --plugin=ckan jobs list -c /etc/ckan/default/production.ini 2>/dev/null)
if [ "$QUEUE" != "" ]; then
    NOW=$(date +'%Y-%m-%dT%H:%M:%S')
    echo "$QUEUE" > /var/log/ckan/ckan-worker-queue.$NOW.log
fi
