#!/usr/bin/env bash
#
# Read-only. Lists what actually exists in bumba's postgres, so the import
# blocks in imports.tf are filled in from reality rather than from memory.
#
#   ./discover.sh
#
# Goes in over ssh + docker exec as the superuser, the same route
# ./bootstrap-state-db.sh uses -- no provider, no state, no tofu.

set -euo pipefail
command -v ssh >/dev/null 2>&1 || { echo "missing 'ssh'" >&2; exit 1; }

DB_CONTAINER="${DB_CONTAINER:-database-db-1}"
if [ -z "${BUMBA_ADDR:-}" ]; then
  BUMBA_ADDR="$(tailscale ip -4 "${BUMBA_TS_HOST:-bumba}" 2>/dev/null)" || {
    echo "cannot resolve bumba on the tailnet; set BUMBA_ADDR" >&2; exit 1; }
fi
SSH_HOST="${SSH_HOST:-root@${BUMBA_ADDR}}"

ssh "$SSH_HOST" docker exec -i "$DB_CONTAINER" psql -U postgres <<'SQL'
\echo '=== databases (tofu_state and the templates are NOT candidates) ==='
SELECT d.datname,
       pg_catalog.pg_get_userbyid(d.datdba) AS owner,
       pg_size_pretty(pg_database_size(d.datname)) AS size,
       d.datconnlimit AS conn_limit,
       pg_encoding_to_char(d.encoding) AS encoding,
       d.datcollate AS lc_collate,
       d.datctype   AS lc_ctype
  FROM pg_database d
 WHERE NOT d.datistemplate
 ORDER BY d.datname;

\echo ''
\echo '=== roles (tofu_state is EXCLUDED from tofu by design) ==='
SELECT r.rolname, r.rolsuper, r.rolcreatedb, r.rolcreaterole,
       r.rolcanlogin, r.rolreplication, r.rolconnlimit,
       r.rolvaliduntil,
       ARRAY(SELECT b.rolname FROM pg_auth_members m
              JOIN pg_roles b ON m.roleid = b.oid
             WHERE m.member = r.oid) AS member_of
  FROM pg_roles r
 WHERE r.rolname NOT LIKE 'pg\_%'
 ORDER BY r.rolname;

\echo ''
\echo '=== installed extensions, per database ==='
-- pg_extension is per-database, so connect to each in turn. \gexec runs the
-- generated \connect + query rather than reporting only the current database.
SELECT format('\\connect %I', datname) || E'\n' ||
       'SELECT current_database() AS db, extname, extversion FROM pg_extension ORDER BY extname;'
  FROM pg_database
 WHERE NOT datistemplate AND datallowconn
 ORDER BY datname
\gexec

\echo ''
\echo '=== server ==='
SELECT version();
SHOW max_connections;
SHOW data_directory;
SQL

cat <<'NEXT'

==> The names above are what imports.tf needs. Two things to leave alone:

      role     tofu_state    the backend's own credential -- see README.md
      database tofu_state    holds this layer's state

    Extensions are listed per database. That matters for what comes later --
    immich needs pgvector, and an extension is a resource
    (postgresql_extension) in its own right.

NEXT
