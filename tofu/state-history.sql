-- Keeps the newest 10 versions of tofu's state, in tofu_infra.states_history.
-- Idempotent. Run against the state database AFTER `tofu init` has created the
-- backend's table:
--
--   . ./env.sh && psql "$PG_CONN_STR" -v ON_ERROR_STOP=1 -f state-history.sql
--
-- The pg backend keeps ONE row per workspace and overwrites it. The failure
-- that matters is not "state was lost" but "state is wrong" -- a half-failed
-- apply, a `tofu state rm` on the wrong address, an `import` bound to the wrong
-- live object -- and every one of those wants yesterday's state.
--
-- Only 10: a version is a full state, 10 MB since the navidrome plugin went into
-- it, and keeping all of them had grown the table to 781 MB by 2026-10-29. The
-- nightly backups of this database reach further back.
--
-- EVERYTHING IS SCHEMA-QUALIFIED, AND THAT IS NOT STYLE. PL/pgSQL resolves
-- names at execution time with the search_path of whoever fires the trigger,
-- and the backend connects with the default one. A first version that relied
-- on this session's search_path failed the first real state write, mid-apply:
--
--   Error saving state: pq: relation "states_history" does not exist (42P01)
--
-- Roll back one version (nothing else running):
--
--   update tofu_infra.states s set data = h.data
--   from (select data from tofu_infra.states_history
--         where name = 'default' order by archived_at desc limit 1) h
--   where s.name = 'default';

BEGIN;

-- The strict version of the backend's session: what resolves here resolves
-- there.
SET LOCAL search_path = '';

CREATE TABLE IF NOT EXISTS tofu_infra.states_history (
  archived_at timestamptz NOT NULL DEFAULT now(),
  name        text        NOT NULL,
  data        text        NOT NULL
);

CREATE INDEX IF NOT EXISTS states_history_name_time
  ON tofu_infra.states_history (name, archived_at DESC);

CREATE OR REPLACE FUNCTION tofu_infra.archive_state() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, tofu_infra
AS $fn$
BEGIN
  INSERT INTO tofu_infra.states_history (name, data) VALUES (OLD.name, OLD.data);

  -- Everything older than the 10th newest. With fewer versions than that the
  -- subquery is NULL and nothing is deleted.
  DELETE FROM tofu_infra.states_history
  WHERE name = OLD.name
    AND archived_at < (SELECT archived_at FROM tofu_infra.states_history
                       WHERE name = OLD.name
                       ORDER BY archived_at DESC OFFSET 9 LIMIT 1);
  RETURN NULL;
END
$fn$;

-- AFTER UPDATE OR DELETE, so it does not depend on how the backend writes.
DROP TRIGGER IF EXISTS states_archive ON tofu_infra.states;
CREATE TRIGGER states_archive
  AFTER UPDATE OR DELETE ON tofu_infra.states
  FOR EACH ROW EXECUTE FUNCTION tofu_infra.archive_state();

COMMIT;
