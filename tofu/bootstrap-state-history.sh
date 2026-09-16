#!/usr/bin/env bash
#
# Adds per-apply state history. Run AFTER `tofu init` has created the backend's
# table. Idempotent -- safe to rerun.
#
#   . ./env.sh && ./bootstrap-state-history.sh
#
# Why: the pg backend keeps ONE row per workspace and overwrites it. The
# failure that matters is not "state was lost" but "state is wrong" -- a
# half-failed apply, a `tofu state rm` on the wrong address, an `import` that
# binds a resource to the wrong live object. Every one of those wants
# yesterday's state, and without this there is no yesterday.
#
# Costs nothing operationally: ~50 KB a row, and it rides along in the pg_dump
# that already goes to samson.
#
# ---------------------------------------------------------------------------
# EVERYTHING BELOW IS FULLY SCHEMA-QUALIFIED, AND THAT IS NOT STYLE.
#
# PL/pgSQL resolves unqualified names at EXECUTION time, using the search_path
# of whoever fired the trigger. The first version of this script set
# search_path for its own session and used bare `states_history`; the self-test
# passed, because it ran in that same session. The BACKEND connects with a
# default search_path, so the first real state write failed with
#
#   Error: Failed to save state
#   Error saving state: pq: relation "states_history" does not exist (42P01)
#
# leaving an errored.tfstate on disk mid-apply. Hence: qualified names, a
# pinned search_path on the function itself, and a self-test that runs with
# search_path emptied so it exercises the backend's conditions, not ours.
# ---------------------------------------------------------------------------

set -euo pipefail
command -v psql >/dev/null 2>&1 || { echo "missing 'psql'" >&2; exit 1; }
: "${PG_CONN_STR:?source ./env.sh first}"

SCHEMA="${SCHEMA:-tofu_infra}"   # must match schema_name in providers.tf
                                 # (named for this module's infra-only origin)

# Substituted into SQL below, so it must be a bare identifier.
[[ "$SCHEMA" =~ ^[a-z_][a-z0-9_]*$ ]] || {
  echo "SCHEMA must be a plain lowercase identifier, got: $SCHEMA" >&2; exit 1; }

# One transaction for the DDL *and* the self-test. Postgres has transactional
# DDL, so a failed test rolls the trigger back out rather than leaving a broken
# one installed -- which is exactly how the first version blocked an apply.
psql "$PG_CONN_STR" -v ON_ERROR_STOP=1 <<SQL
BEGIN;

-- Emptied, not set: this is the strict version of what the backend's session
-- looks like. Anything that resolves here resolves there.
SET LOCAL search_path = '';

DO \$chk\$
BEGIN
  IF to_regclass('${SCHEMA}.states') IS NULL THEN
    RAISE EXCEPTION 'table ${SCHEMA}.states does not exist -- run \`tofu init\` first';
  END IF;
END
\$chk\$;

CREATE TABLE IF NOT EXISTS ${SCHEMA}.states_history (
  archived_at timestamptz NOT NULL DEFAULT now(),
  name        text        NOT NULL,
  data        text        NOT NULL
);

CREATE INDEX IF NOT EXISTS states_history_name_time
  ON ${SCHEMA}.states_history (name, archived_at DESC);

CREATE OR REPLACE FUNCTION ${SCHEMA}.archive_state() RETURNS trigger
LANGUAGE plpgsql
-- Pinned so the function does not depend on the caller's search_path at all.
SET search_path = pg_catalog, ${SCHEMA}
AS \$fn\$
BEGIN
  INSERT INTO ${SCHEMA}.states_history (name, data) VALUES (OLD.name, OLD.data);
  RETURN NULL;
END
\$fn\$;

-- AFTER UPDATE OR DELETE, so it does not depend on how the backend chooses to
-- write. DROP/CREATE rather than CREATE OR REPLACE: older postgres has no
-- CREATE OR REPLACE TRIGGER.
DROP TRIGGER IF EXISTS states_archive ON ${SCHEMA}.states;
CREATE TRIGGER states_archive
  AFTER UPDATE OR DELETE ON ${SCHEMA}.states
  FOR EACH ROW EXECUTE FUNCTION ${SCHEMA}.archive_state();

-- Prove it fires, on a row of our own. The real state row is not usable for
-- this: it does not exist before the first write, and mangling it would be a
-- poor way to test a safety net.
INSERT INTO ${SCHEMA}.states (name, data) VALUES ('__trigger_selftest__', '{}');
UPDATE ${SCHEMA}.states SET data = '{"selftest":1}' WHERE name = '__trigger_selftest__';

DO \$chk\$
DECLARE n bigint;
BEGIN
  SELECT count(*) INTO n
    FROM ${SCHEMA}.states_history WHERE name = '__trigger_selftest__';
  IF n < 1 THEN
    RAISE EXCEPTION 'trigger did not fire: no history row for the self-test';
  END IF;
  RAISE NOTICE 'trigger fired (% row archived); cleaning up', n;
END
\$chk\$;

-- The DELETE archives one more row, hence clearing history by name last.
DELETE FROM ${SCHEMA}.states         WHERE name = '__trigger_selftest__';
DELETE FROM ${SCHEMA}.states_history WHERE name = '__trigger_selftest__';

COMMIT;
SQL

cat <<NEXT

==> ${SCHEMA}.states_history is live and verified.

    Inspect:
      psql "\$PG_CONN_STR" -c \\
        "select archived_at, name, pg_size_pretty(length(data)::bigint) \\
         from ${SCHEMA}.states_history order by archived_at desc limit 10"

    Roll back one generation (nothing should be running):
      psql "\$PG_CONN_STR" -c \\
        "update ${SCHEMA}.states s set data = h.data \\
         from (select data from ${SCHEMA}.states_history \\
               where name = 'default' order by archived_at desc limit 1) h \\
         where s.name = 'default'"

NEXT
