#!/bin/sh
# Trigger archiver update to bulk queue

/usr/lib/ckan/default/bin/paster --plugin=ckanext-archiver archiver update -c /etc/ckan/default/production.ini