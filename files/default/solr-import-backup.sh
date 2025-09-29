#!/bin/sh

# Specify a (local) path to a Solr index snapshot archive.
# This script will import the index into the local Solr instance.
# This will cause a brief outage, as Solr will be stopped
# and its index overwritten with the snapshot.
# No attempt is made to interact with other Solr instances.

if [ "$(whoami)" != "root" ] || [ "$#" -lt 1 ]; then
    echo "Usage: $0 <archive path>" >&2
    echo "$0 must be run as root"
    exit 1
fi

. `dirname $0`/solr-env.sh

SOLR_DIR=/var/solr/data/$CORE_NAME/data
ARCHIVE_NAME=$1

echo "Importing Solr index from ${ARCHIVE_NAME}..."
systemctl stop solr
sudo -u solr rm -f $SOLR_DIR/index.properties
sudo -u solr mkdir $SOLR_DIR/index
sudo -u solr tar -C $SOLR_DIR/index -xvzf $ARCHIVE_NAME
systemctl start solr
