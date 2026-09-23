#!/bin/sh
# Tells gatus whether a snapshot has actually been taken recently.
#
# THIS FILE IS PUBLIC. The bearer token is read from a mounted file.
#
# Runs INSIDE the kopia container, backgrounded by the entrypoint, because
# that is the only place the repository password already exists. A separate
# checker container -- the shape used for databasus -- would need its own copy
# of that credential to ask the same question, which is a worse trade than a
# background loop.
#
# It reports on the REPOSITORY, not on this process. "kopia is running" was
# never the claim worth checking: this estate has had kopia crash-looping for
# five weeks and kopia cleanly stopped for four days, and in both cases the
# container and the repository disagreed about whether backups existed.
#
# Three ways the endpoint goes red, and they are deliberately different:
#
#   newest snapshot older than MAX_AGE   pushed as success=false
#   this loop dies, or the container is  no push at all -- gatus's own
#     down, or the whole host is down      heartbeat interval expires
#   the repository cannot be read        no push; see below
#
# A failed query pushes NOTHING rather than false. It is usually transient (a
# snapshot holding a lock, a slow Storage Box) and a false would page within
# three sweeps. Sustained failure still surfaces, via the heartbeat, just more
# slowly -- which is the right way round for a check that must not cry wolf.

set -u

: "${HEARTBEAT_MAX_AGE:=93600}" # 26h: the daily 05:00 run plus a slow night
: "${HEARTBEAT_INTERVAL:=3600}"
: "${HEARTBEAT_START_DELAY:=120}"

CONFIG=/app/repository.config
TOKEN_FILE=/run/secrets/gatus_token
ENDPOINT=backups_kopia-mindy

push() { # push true|false
  curl -fsS -m 30 -X POST \
    -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
    "${GATUS_BASE}/${ENDPOINT}/external?success=$1" \
    -o /dev/null 2>&1 || echo "heartbeat: push failed ($1)"
}

# The newest snapshot across every source, as kopia prints it:
#   "  2026-09-23 05:00:04 UTC kbf74... 2.1 MB ..."
# Sorting the timestamps lexically works because they are zero-padded ISO.
newest_snapshot() {
  kopia snapshot list --all --config-file="$CONFIG" 2>/dev/null |
    grep -oE '^  [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]+' |
    sort | tail -1 | sed 's/^  *//'
}

# The repository is on a Storage Box over SFTP and the first query after start
# competes with the policy import above it in the entrypoint.
sleep "$HEARTBEAT_START_DELAY"

while true; do
  newest="$(newest_snapshot)"

  if [ -z "$newest" ]; then
    echo "heartbeat: could not read the repository -- not pushing"
  else
    age=$(($(date +%s) - $(date -d "$newest UTC" +%s)))
    if [ "$age" -le "$HEARTBEAT_MAX_AGE" ]; then
      echo "heartbeat: ok, newest snapshot $newest UTC (${age}s old)"
      push true
    else
      echo "heartbeat: STALE, newest snapshot $newest UTC (${age}s old, max ${HEARTBEAT_MAX_AGE})"
      push false
    fi
  fi

  sleep "$HEARTBEAT_INTERVAL"
done
