#!/bin/bash
# Makes the postgres SUPERUSER password declarative, then starts postgres.
#
# THIS FILE IS PUBLIC. The password arrives in a mounted file, never an
# argument or an environment variable -- `docker inspect` and `ps` both show
# those.
#
# The problem it solves: POSTGRES_PASSWORD is read by initdb and ONLY by
# initdb, on an EMPTY data directory. On a cluster that already exists, tofu
# can set that variable and change nothing, so the superuser password was the
# one credential tofu defined at creation and could never touch again. That is
# why it had to be supplied by hand, and why rotating it was a runbook.
#
# Re-asserting it on every start fixes that. `local all all trust` in the
# image's generated pg_hba.conf means a connection over the unix socket inside
# this container needs no password -- so the container can always set its own
# superuser password, including when nobody knows what it currently is.
#
# WHAT THIS MUST NEVER DO IS STOP POSTGRES FROM STARTING. The assertion runs in
# the background and its failure is reported, not fatal. A cluster that will
# not boot because a password-setting helper had a bad day is a far worse
# outcome than a password that is one rotation behind.
#
# Success is published as a marker file, which the container's healthcheck
# requires. That is what lets tofu wait for the new password to be live before
# the postgresql provider tries to use it -- see docker_container.postgres.

set -u

PASSWORD_FILE=/run/secrets/postgres_superuser_password
MARKER=/tmp/.superuser-password-asserted

assert() {
  # A fresh container never has the marker; a restarted one might, and
  # re-asserting the same password is harmless either way.
  rm -f "$MARKER"

  if [ ! -r "$PASSWORD_FILE" ]; then
    echo "assert-superuser-password: $PASSWORD_FILE missing, skipping" >&2
    return 1
  fi

  # 120 x 1s. initdb on a new cluster is the slow case; an existing one is
  # ready in a couple of seconds.
  local i=0
  while ! pg_isready -q -U postgres 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 120 ]; then
      echo "assert-superuser-password: postgres not ready after 120s" >&2
      return 1
    fi
    sleep 1
  done

  # Passed via a psql variable, not interpolated into the SQL text, so a
  # password containing a quote cannot end the string early or run anything.
  # :'v' expands to a correctly quoted literal.
  #
  # On STDIN, not -c. psql does not perform variable interpolation on -c: the
  # server receives the literal ":'v'" and fails with `syntax error at or near
  # ":"`. Found by running this against postgres:17 before it went near the
  # real cluster -- the ALTER failed silently apart from one line in the log,
  # which is exactly how a password rotation would have quietly stopped
  # happening.
  if psql -v ON_ERROR_STOP=1 -U postgres -d postgres --no-psqlrc \
       -v v="$(cat "$PASSWORD_FILE")" \
       >/dev/null 2>&1 <<<"ALTER USER postgres PASSWORD :'v';"; then
    touch "$MARKER"
    echo "assert-superuser-password: superuser password asserted"
    return 0
  fi

  echo "assert-superuser-password: ALTER USER failed -- the cluster keeps its previous password" >&2
  return 1
}

assert &

# Hand off to the image's own entrypoint, replacing this shell so postgres
# keeps PID 1 and signals still reach it.
#
# REAL_ENTRYPOINT, not a hardcoded path. immich's postgres image does NOT boot
# through docker-entrypoint.sh: it wraps it with immich-docker-entrypoint.sh,
# which installs the tuned postgresql.conf from a template, substitutes PGDATA
# into it and sources set-env.sh. Skipping that costs you
# `shared_preload_libraries = vchord.so, vectors.so` -- so the cluster comes up
# and immich's vector extensions do not.
#
# Left as a variable rather than that path, because the same wrapper is meant
# for bumba and mindy, whose stock images boot the plain entrypoint.
exec "${REAL_ENTRYPOINT:-/usr/local/bin/docker-entrypoint.sh}" "$@"
