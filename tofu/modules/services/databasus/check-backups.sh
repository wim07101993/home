#!/bin/sh
# Reports each databasus dump to gatus, hourly, forever.
#
# THIS FILE IS PUBLIC. Everything it needs arrives in the environment.
#
# Why a file check and not databasus's own webhook: databasus can tell you what
# IT thinks happened, and the two failures this estate has actually had were
# both invisible from that angle.
#
#   - 2026-09-22: kitchenowl, memos and score had no target configured at all.
#     Nothing failed, so nothing was reported. The dashboard was green because
#     the dashboard only knew about the two that existed.
#   - earlier: a run of dumps landed at 64 bytes each. databasus knew -- it
#     wrote no .metadata beside them -- and the mail went nowhere anyone read.
#
# A check that reads the directory has neither blind spot: a database that
# stops being dumped goes stale, and a dump that is written but useless is too
# small. Both are properties of the artifact, which is the thing being relied
# on when it matters.
#
# Environment:
#   CHECKS      space-separated  <key>:<file-prefix>:<min-bytes>
#   GATUS_BASE  https://status.wvl.app/api/v1/endpoints
#   GATUS_TOKEN bearer token for the external endpoints
#   MAX_AGE     seconds before the newest dump counts as stale
#   INTERVAL    seconds between sweeps
#
# Endpoint names are `backups_databasus-<key>`, matching the external-endpoints
# in ../gatus/config.yaml. A key that exists on one side and not the other is
# not an error here -- gatus 404s the push, and its own heartbeat takes the
# endpoint down. Failing towards "down" is the point.

set -u

: "${MAX_AGE:=93600}"  # 26h: daily dump plus room for a slow run
: "${INTERVAL:=3600}"

# Prints the newest dump for a prefix, or nothing.
#
# The .metadata sidecar is excluded because it is always ~174 bytes and always
# newer than nothing -- matching it would mean every database passes the size
# floor on a file that contains no data.
newest() {
  ls -t "/backups/$1"-* 2>/dev/null | grep -v '\.metadata$' | head -1
}

# Pushes one result. Failures to reach gatus are deliberately not retried: the
# next sweep is an hour away and the heartbeat covers a long silence, so a retry
# loop here would only add a way for this script to hang.
push() {
  curl -fsS -m 30 -X POST \
    -H "Authorization: Bearer ${GATUS_TOKEN}" \
    "${GATUS_BASE}/backups_databasus-$1/external?success=$2" \
    -o /dev/null 2>&1 ||
    echo "push failed: $1=$2"
}

sweep() {
  now="$(date +%s)"
  for spec in ${CHECKS}; do
    key="${spec%%:*}"
    rest="${spec#*:}"
    prefix="${rest%%:*}"
    floor="${rest#*:}"

    file="$(newest "${prefix}")"
    if [ -z "${file}" ]; then
      echo "${key}: no dump found"
      push "${key}" false
      continue
    fi

    age="$((now - $(stat -c %Y "${file}")))"
    size="$(stat -c %s "${file}")"

    if [ "${age}" -gt "${MAX_AGE}" ]; then
      echo "${key}: stale, ${age}s old (max ${MAX_AGE})"
      push "${key}" false
    elif [ "${size}" -lt "${floor}" ]; then
      echo "${key}: too small, ${size} bytes (min ${floor})"
      push "${key}" false
    else
      echo "${key}: ok, ${size} bytes, ${age}s old"
      push "${key}" true
    fi
  done
}

# Sweep before the first sleep, so a restart reports immediately rather than
# leaving every endpoint on its last known value for an hour.
while true; do
  sweep
  sleep "${INTERVAL}"
done
