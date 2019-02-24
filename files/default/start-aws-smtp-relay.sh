#!/bin/sh
PIDFILE=/var/run/aws-smtp-relay.pid
if [ -e $PIDFILE ]; then
  PID=`head -1 $PIDFILE`
  ps -p $PID > /dev/null && echo "Relay process already found with PID $PID" && exit 1
fi

java -jar /usr/share/aws-smtp-relay/aws-smtp-relay-1.0.0-jar-with-dependencies.jar -p 25 -r us-east-1 &
echo $! > $PIDFILE
