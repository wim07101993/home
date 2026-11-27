#!/usr/bin/env bash
#
# Moves the postgres clusters on mindy and bumba to the major version that
# modules/services/postgres/main.tf names. Bump that tag first, then run this
# from a shell where env.sh has been sourced.
#
# A major version cannot start on the previous major's data directory, so per
# host this is a dump and restore, not a container swap:
#
#   stop the clients -> pg_dumpall -> stop db -> data/ moves to data-pg<old>/
#   -> tofu replaces db, which initdbs an empty data/ -> restore -> compare
#   row counts with the ones taken before the dump -> start the clients
#
# mindy goes first: same procedure, without the state backend in the way.
# bumba's postgres IS the state backend, so its turn happens with the state
# moved to a local (still encrypted) file, and moved back afterwards.
#
# Nothing is deleted. The old data directories stay on the hosts and the dumps
# stay on this machine; the summary at the end says where.

set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

NEW_IMAGE=$(sed -nE 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"(postgres:[^"]+)".*/\1/p' modules/services/postgres/main.tf)
[[ $NEW_IMAGE =~ ^postgres:([0-9]+) ]] || { echo "cannot read the postgres image from modules/services/postgres/main.tf" >&2; exit 1; }
NEW_MAJOR=${BASH_REMATCH[1]}

DUMP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pg-major-upgrade/$(date +%Y%m%dT%H%M%S)"

# What to do by hand if the script stops here. Updated before every step that
# leaves something half done. state_hint is set while the state is local, and
# stays in front of whatever bumba's own steps put in recovery.
recovery="nothing has changed yet."
state_hint=""

print_recovery() {
  printf '\nStopped. State of things and how to recover:\n%s%s\n' "$state_hint" "$recovery" >&2
}

trap 'echo "failed at line $LINENO" >&2; print_recovery' ERR

log() { printf '\n==> %s\n' "$*"; }

die() { echo "$*" >&2; print_recovery; exit 1; }

remote_docker() {   # remote_docker <addr> <docker args...>
  docker -H "ssh://wim@$1" "${@:2}"
}

# Runs a postgres client tool from the NEW image against a host's cluster, so
# the dump is written by the new major's pg_dumpall, as its release notes ask.
pg_client() {   # pg_client <addr> <password> <command...>
  PGPASSWORD="$2" docker run --rm --network host \
    -e PGPASSWORD -e PGHOST="$1" -e PGPORT=5432 -e PGUSER=postgres \
    "$NEW_IMAGE" "${@:3}" </dev/null
}

server_major() {   # server_major <addr> <password>
  local num
  num=$(pg_client "$1" "$2" psql -d postgres -Atc 'show server_version_num')
  echo $(( num / 10000 ))
}

# "<database> <schema.table> <rows>" for every table in every database.
row_counts_per_table() {   # row_counts_per_table <addr> <password>
  local db dbs
  dbs=$(pg_client "$1" "$2" psql -d postgres -Atc \
    "select datname from pg_database where datallowconn and not datistemplate order by 1")
  for db in $dbs; do
    pg_client "$1" "$2" psql -d "$db" -At -F ' ' -c "
      select format('%I.%I', table_schema, table_name),
             (xpath('/row/c/text()', query_to_xml(
               format('select count(*) as c from %I.%I', table_schema, table_name),
               false, true, '')))[1]::text
      from information_schema.tables
      where table_type = 'BASE TABLE'
        and table_schema not in ('pg_catalog', 'information_schema')
      order by 1" | sed "s/^/$db /"
  done
}

# Exits non-zero when the databasus image this repo deploys cannot dump the
# new major: its bundled pg_dump refuses a newer server.
databasus_supports_new_major() {
  local image
  image=$(sed -nE 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"(databasus\/[^"]+)".*/\1/p' modules/services/databasus/main.tf)
  docker run --rm --entrypoint test "$image" \
    -x "/app/assets/tools/x64/postgresql/postgresql-$NEW_MAJOR/bin/pg_dump"
}

upgrade_cluster() {   # upgrade_cluster <host> <tofu module address> <client containers...>
  local host=$1 module=$2
  local clients=("${@:3}")
  local addr_var="TF_VAR_${host}_addr" pw_var="TF_VAR_${host}_pg_superuser_password"
  local addr=${!addr_var} pw=${!pw_var}
  local old_major dir="$DUMP_DIR/$host"
  old_major=$(server_major "$addr" "$pw")
  mkdir -p "$dir"

  log "$host: stopping ${clients[*]}"
  recovery="$host: clients may be stopped, the database is untouched.
  start them: docker -H ssh://wim@$addr start ${clients[*]}"
  remote_docker "$addr" stop "${clients[@]}"

  log "$host: counting rows and dumping postgres $old_major"
  row_counts_per_table "$addr" "$pw" >"$dir/rows-before.txt"
  pg_client "$addr" "$pw" pg_dumpall >"$dir/dumpall.sql"
  grep -q '^-- PostgreSQL database cluster dump complete' "$dir/dumpall.sql" \
    || die "$host: the dump in $dir/dumpall.sql is incomplete"

  log "$host: stopping db and moving data/ to data-pg$old_major/"
  recovery="$host: db is stopped, its data may already be in /docker-volumes/db/data-pg$old_major.
  to roll back:
    docker -H ssh://wim@$addr run --rm -v /docker-volumes/db:/db $NEW_IMAGE sh -c 'rm -rf /db/data && mv /db/data-pg$old_major /db/data'
    docker -H ssh://wim@$addr start db ${clients[*]}"
  remote_docker "$addr" stop db
  remote_docker "$addr" run --rm -v /docker-volumes/db:/db "$NEW_IMAGE" sh -euc "
    test ! -e /db/data-pg$old_major
    mv /db/data /db/data-pg$old_major
    install -d -o postgres -g postgres -m 700 /db/data"

  log "$host: replacing db with $NEW_IMAGE (review the plan: only $module)"
  recovery="$host: the old cluster is untouched in /docker-volumes/db/data-pg$old_major, the dump in $dir/dumpall.sql.
  to roll back: put the old tag back in modules/services/postgres/main.tf, then
    docker -H ssh://wim@$addr stop db
    docker -H ssh://wim@$addr run --rm -v /docker-volumes/db:/db $NEW_IMAGE sh -c 'rm -rf /db/data && mv /db/data-pg$old_major /db/data'
    tofu apply -target=$module
    docker -H ssh://wim@$addr start ${clients[*]}"
  tofu apply -target="$module"
  [[ $(server_major "$addr" "$pw") == "$NEW_MAJOR" ]] || die "$host: db is not on postgres $NEW_MAJOR after the apply"

  log "$host: restoring"
  # "role postgres already exists" is the only expected error: initdb made it.
  PGPASSWORD="$pw" docker run --rm -i --network host \
    -e PGPASSWORD -e PGHOST="$addr" -e PGPORT=5432 -e PGUSER=postgres \
    "$NEW_IMAGE" psql -d postgres -q -o /dev/null <"$dir/dumpall.sql" 2>"$dir/restore-errors.txt"
  if grep -v 'role "postgres" already exists' "$dir/restore-errors.txt" | grep -q 'ERROR'; then
    die "$host: the restore reported errors, see $dir/restore-errors.txt"
  fi
  pg_client "$addr" "$pw" vacuumdb --all --analyze-in-stages

  row_counts_per_table "$addr" "$pw" >"$dir/rows-after.txt"
  diff "$dir/rows-before.txt" "$dir/rows-after.txt" \
    || die "$host: row counts differ between the old and the new cluster (left: before)"

  log "$host: starting ${clients[*]}"
  remote_docker "$addr" start "${clients[@]}"

  recovery="$host is done (old data in /docker-volumes/db/data-pg$old_major)."
}

# --- preflight --------------------------------------------------------------

for v in TF_VAR_state_passphrase PG_CONN_STR TF_VAR_bumba_addr TF_VAR_mindy_addr \
         TF_VAR_bumba_pg_superuser_password TF_VAR_mindy_pg_superuser_password; do
  [[ -n ${!v:-} ]] || die "$v is not set; source env.sh first."
done

[[ ! -e backend_override.tf && ! -e terraform.tfstate ]] \
  || die "backend_override.tf or terraform.tfstate exists: an earlier run left the state local. Sort that out first."

docker pull -q "$NEW_IMAGE" >/dev/null

bumba_major=$(server_major "$TF_VAR_bumba_addr" "$TF_VAR_bumba_pg_superuser_password")
mindy_major=$(server_major "$TF_VAR_mindy_addr" "$TF_VAR_mindy_pg_superuser_password")
echo "bumba runs postgres $bumba_major, mindy runs $mindy_major, main.tf asks for $NEW_IMAGE"

for m in "$bumba_major" "$mindy_major"; do
  (( m <= NEW_MAJOR )) || die "a host runs a newer major than $NEW_IMAGE"
done
(( bumba_major < NEW_MAJOR || mindy_major < NEW_MAJOR )) \
  || die "both hosts already run $NEW_MAJOR. Bump the tag in modules/services/postgres/main.tf first."

if ! databasus_supports_new_major; then
  echo
  echo "WARNING: databasus has no pg_dump $NEW_MAJOR. Backups of both clusters fail until it does."
  read -rp "Type 'no backups' to continue anyway: " answer
  [[ $answer == "no backups" ]] || die "stopped."
fi

echo
echo "This stops memos, kitchen-owl and score-api on mindy, and zitadel (every login) on bumba,"
echo "each for the time its dump, initdb and restore take. Dumps go to $DUMP_DIR."
read -rp "Continue? [y/N] " answer
[[ $answer == [yY] ]] || die "stopped."

umask 077
mkdir -p "$DUMP_DIR"

# --- mindy --------------------------------------------------------------------

if (( mindy_major < NEW_MAJOR )); then
  upgrade_cluster mindy module.mindy_postgres memos kitchen-owl score-api
fi

# --- bumba, with the state on a local file --------------------------------------

if (( bumba_major < NEW_MAJOR )); then
  log "moving the state from bumba's postgres to a local file"
  recovery="the state may be local already (tofu/terraform.tfstate, behind tofu/backend_override.tf).
  to move it back: rm backend_override.tf && tofu init -migrate-state -force-copy"
  printf 'terraform {\n  backend "local" {}\n}\n' >backend_override.tf
  tofu init -migrate-state -force-copy

  state_hint="THE STATE IS LOCAL (tofu/terraform.tfstate). Do not run tofu without backend_override.tf
until it is moved back, which needs bumba's postgres up:
  rm backend_override.tf && tofu init -migrate-state -force-copy
"

  upgrade_cluster bumba module.postgres_bumba zitadel

  log "moving the state back to bumba's postgres"
  rm backend_override.tf
  # -force-copy answers yes to overwriting the copy in pg, which the restore
  # brought back exactly as it was before the db was replaced.
  tofu init -migrate-state -force-copy
  state_hint=""
  mv terraform.tfstate* "$DUMP_DIR/" 2>/dev/null || true
fi

# --- verify -----------------------------------------------------------------

log "checking that tofu agrees with what runs"
rc=0
tofu plan -target=module.mindy_postgres -target=module.postgres_bumba -detailed-exitcode || rc=$?
(( rc == 0 )) || die "tofu still plans changes to the postgres modules (exit $rc)."

cat <<EOF

Done. Both clusters run $NEW_IMAGE.

Still to do by hand:
  - databasus: open every database on mindy and bumba and save it once. It keeps the
    server version it detected when the database was saved, and runs that version's
    pg_dump; until it is saved again it runs pg_dump $bumba_major against $NEW_MAJOR and fails.
    Then run a backup of each by hand.
  - tofu plan for everything else; nothing outside the two postgres modules was applied.
  - once happy, remove the old clusters:
      /docker-volumes/db/data-pg$mindy_major on mindy   (if mindy was upgraded)
      /docker-volumes/db/data-pg$bumba_major on bumba   (if bumba was upgraded)
  - $DUMP_DIR holds plaintext dumps of every database (zitadel included). Delete it.
EOF
