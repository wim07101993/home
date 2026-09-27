#!/bin/sh
# Creates the FIRST snapshot for each source, and only the first.
#
# THIS FILE IS PUBLIC. Everything it needs arrives in the environment, and the
# repository password is already exported by the entrypoint that backgrounds
# this.
#
# Why it exists: kopia's scheduler only runs for sources it already knows, and
# a source does not exist until something has snapshotted the path once.
# Mounting a directory and writing a policy is not enough. samson came up on
# 2026-09-24 with all three paths mounted, correct policies, a healthy server
# -- and `kopia snapshot list` empty. It would have sat there indefinitely
# backing up nothing, with only the gatus heartbeat to say so.
#
# mindy never needed this because its sources were created years ago, over NFS,
# by hand. That is exactly the kind of history a second instance does not
# inherit.
#
# Environment:
#   SOURCES  space-separated container paths, e.g. "/data/media /data/backups"

set -u

CONFIG=/app/repository.config

# The first pass over a large source reads everything to hash it -- for samson
# that is ~800 GB off the array. Backgrounded by the entrypoint so the server
# comes up immediately and the UI works while this runs.
# NEWLINE, not the default whitespace split: these paths contain spaces.
# `The Lion King (1994)` is one source, not three.
IFS='
'
for src in ${SOURCES:-}; do
  # Count SNAPSHOT ROWS, not any output. `kopia snapshot list <path>` prints
  # the source header even when the source has zero snapshots, so a bare
  # `grep -q .` matches and the source is skipped -- leaving it registered,
  # never snapshotted, and never scheduled. Which is precisely the failure this
  # script exists to prevent, and it silently did exactly that to
  # root@samson:/data/media on 2026-09-25.
  #
  # Snapshot rows begin with two spaces and an ISO date.
  if kopia snapshot list "$src" --config-file="$CONFIG" 2>/dev/null | grep -qE '^  [0-9]{4}-[0-9]{2}-[0-9]{2}'; then
    echo "bootstrap: $src already has snapshots, leaving it to the scheduler"
    continue
  fi

  echo "bootstrap: $src has no snapshots -- creating the first one"

  # NOT gated. A failure here must not stop the others: one unreadable source
  # should cost one source, not the whole host's backups.
  if kopia snapshot create "$src" --config-file="$CONFIG"; then
    echo "bootstrap: $src done"
  else
    echo "bootstrap: $src FAILED -- it will not be scheduled until this succeeds" >&2
  fi
done

# --- prune: sources that are no longer declared -------------------------
#
# Without this the model is only half declarative. Adding a path to
# var.sources creates a kopia source; REMOVING one leaves it in the
# repository, still scheduled, forever. That is not a hypothetical --
# root@samson:/data/media outlived its config on 2026-09-25, inherited the
# global schedule, and was primed to snapshot 8.4 TB into 4.5 TB of free
# space.
#
# This is the counterpart to `--delete-other-policies`: the declared list is
# authoritative, and anything else belonging to THIS identity goes.
#
# IT DELETES SNAPSHOTS. Two guards, because a typo here destroys backups:
#
#   - scoped to this instance's own <user>@<host> prefix, so one host can
#     never delete another's -- mindy cannot drop samson's sources
#   - off unless PRUNE_SOURCES=true, so a new instance cannot prune before
#     anyone has looked at what it would remove
#
# It runs AFTER the create loop above, so a source being moved between hosts
# is created on the new one before being dropped from the old.
if [ "${PRUNE_SOURCES:-false}" = "true" ]; then
  mine="${KOPIA_IDENTITY:?PRUNE_SOURCES needs KOPIA_IDENTITY}"

  kopia snapshot list --all --config-file="$CONFIG" 2>/dev/null |
    grep -oE "^${mine}:.*$" | sort -u |
  while IFS= read -r existing; do
    path="${existing#"${mine}":}"

    # Declared? Exact match against the newline-separated list.
    if printf '%s\n' ${SOURCES:-} | grep -qxF "$path"; then
      continue
    fi

    echo "prune: $existing is no longer declared -- deleting it and its snapshots"
    if kopia snapshot delete --all-snapshots-for-source "$existing" --delete \
         --config-file="$CONFIG"; then
      echo "prune: $existing deleted"
    else
      echo "prune: $existing FAILED to delete" >&2
    fi
  done
fi
