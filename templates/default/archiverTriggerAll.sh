#!/bin/sh
# Trigger archiver update to bulk queue

PASTER_PLUGIN=ckanext-archiver /usr/lib/ckan/default/bin/ckan_cli archiver update
