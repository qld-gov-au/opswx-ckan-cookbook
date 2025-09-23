#!/bin/sh
# Trigger the collection of statistics

VIRTUAL_ENV=${VIRTUAL_ENV:-/usr/lib/ckan/default}

$VIRTUAL_ENV/bin/ckan_cli selfinfo write-selfinfo-duplicated-env

