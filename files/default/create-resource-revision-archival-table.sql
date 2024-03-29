CREATE TABLE resource_revision_archive (
 id text,
 url text,
 format text,
 description text,
 position integer,
 revision_id text,
 continuity_id text,
 hash text,
 state text,
 extras text,
 expired_id text,
 revision_timestamp timestamp,
 expired_timestamp timestamp,
 current boolean,
 name text,
 resource_type text,
 mimetype text,
 mimetype_inner text,
 size bigint,
 last_modified timestamp,
 cache_url text,
 cache_last_updated timestamp,
 webstore_url text,
 webstore_last_updated timestamp,
 created timestamp,
 url_type text,
 package_id text
)
