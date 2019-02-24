#!/bin/sh
PIDFILE=/var/run/aws-smtp-relay.pid
if [ -e $PIDFILE ]; then
  head -1 $PIDFILE | xargs kill
  rm $PIDFILE
fi
