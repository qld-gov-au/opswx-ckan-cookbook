#!/bin/sh

if (/usr/local/bin/pick-solr-master.sh); then
  rsync -a /var/solr/data/ /data/solr/data/
else
  service solr stop
  rsync -a /data/solr/data/ /var/solr/data/
  service solr start
fi
