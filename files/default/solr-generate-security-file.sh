#!/bin/sh

# Generate a Solr security configuration file (security.json)
# and output to STDOUT.
# Expects the Solr password to be passed as a parameter.

if [ $# -ne 1 ]; then
    echo "Usage: $0 <password>" >&2
    exit 1
fi

PASSWORD="$1"
SALT_BYTES=$(openssl rand 32)
SALT_TEXT=$(echo -n "$SALT_BYTES" | base64)
PASSWORD_HASH=$(echo -n "${SALT_BYTES}${PASSWORD}" |openssl dgst -sha256 -binary | openssl dgst -sha256 -binary |base64)
cat << EOF
{
    "authentication": {
        "blockUnknown": true,
        "class":"solr.BasicAuthPlugin",
        "credentials":{"solr": "$PASSWORD_HASH $SALT_TEXT"}
    }
}
EOF
