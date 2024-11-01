#!/bin/sh

. `dirname $0`/psql-env-ckan.sh

psql $*
