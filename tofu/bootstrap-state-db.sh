#!/usr/bin/env bash
#
# Step 1 of 2. Creates the postgres role and database that hold OpenTofu state,
# on bumba. Run ONCE, before the first `tofu init`. Idempotent -- safe to rerun.
#
#   ./bootstrap-state-db.sh
#
# The tofu_state role is created HERE, by hand, and must never become a
# `postgresql_role` resource in the workload layer. If tofu managed it, the
# credential needed to read state would live inside the state it unlocks, and
# a routine password rotation would lock you out of your own tooling.
# README.md, "The one credential tofu must never manage".

set -euo pipefail

for c in ssh psql; do
  command -v "$c" >/dev/null 2>&1 || { echo "missing '$c'" >&2; exit 1; }
done

DB_CONTAINER="${DB_CONTAINER:-database-db-1}"   # `docker ps` on bumba to confirm

# env.sh takes TOFU_STATE_DB_PASSWORD from the environment or prompts for it.
# Choose the password yourself -- this script does not invent one, so whatever
# you keep it in stays the single source of truth.
. ./env.sh

if [ -z "${TOFU_STATE_DB_PASSWORD:-}" ]; then
  # Only reachable when PG_CONN_STR was supplied directly, so env.sh never
  # needed the password on its own.
  echo "TOFU_STATE_DB_PASSWORD is unset (PG_CONN_STR was given directly)." >&2
  echo "Export it, or unset PG_CONN_STR and rerun." >&2
  exit 1
fi
PW="$TOFU_STATE_DB_PASSWORD"

# ssh by tailnet IP, not by name. Host names here carry a .home suffix that the
# resolver does not always apply, and env.sh has already resolved the address
# anyway -- which also keeps this connection on the tailnet by construction.
# Override SSH_HOST if you would rather use an ssh_config alias.
SSH_HOST="${SSH_HOST:-root@${BUMBA_ADDR:-${BUMBA_TS_HOST:-bumba}}}"

echo "==> creating role and database on ${SSH_HOST} / ${DB_CONTAINER}"

# ssh forwards its stdin to the remote command, which is what carries the
# heredoc to psql. (Contrast with a heredoc that *contains* an ssh call --
# there the inner ssh eats the rest of the script and you need `ssh -n`.)
# Build the SQL string literal HERE, with standard SQL escaping (double the
# single quotes), rather than letting psql's \set or a remote shell re-parse
# the password. standard_conforming_strings is on by default in PG 17, so
# backslashes inside the literal are literal.
PW_SQL="'${PW//\'/\'\'}'"

# ssh forwards its stdin to the remote command, which is what carries the
# heredoc to psql. (Contrast with a heredoc that *contains* an ssh call --
# there the inner ssh eats the rest of the script and you need `ssh -n`.)
ssh "$SSH_HOST" \
  docker exec -i "$DB_CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres <<SQL
-- Session GUC, deliberately not SET LOCAL: psql autocommits each statement, so
-- a LOCAL setting would warn and vanish before the DO block could read it.
SET bootstrap.pw = ${PW_SQL};

-- Role. Rerunning realigns the password with the one supplied rather than
-- failing, so whatever you keep it in stays authoritative if the two drift.
DO \$do\$
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'tofu_state') THEN
    EXECUTE format('ALTER ROLE tofu_state LOGIN PASSWORD %L', current_setting('bootstrap.pw'));
    RAISE NOTICE 'role tofu_state existed; password realigned';
  ELSE
    EXECUTE format('CREATE ROLE tofu_state LOGIN PASSWORD %L', current_setting('bootstrap.pw'));
    RAISE NOTICE 'role tofu_state created';
  END IF;
END
\$do\$;

RESET bootstrap.pw;

-- A dedicated database, not a schema inside an application database: a
-- DROP DATABASE during app surgery must not be able to take state with it.
-- CREATE DATABASE cannot run inside DO or a transaction, hence \gexec.
SELECT 'CREATE DATABASE tofu_state OWNER tofu_state'
 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'tofu_state')
\gexec
SQL

echo "==> verifying the connection the backend will actually use"
psql "$PG_CONN_STR" -Atc 'select current_user, current_database()'

cat <<'NEXT'

==> done. Next:

      . ./env.sh        # if you are in a fresh shell
      tofu init
      ./bootstrap-state-history.sh     # step 2, AFTER init creates the table

NEXT
