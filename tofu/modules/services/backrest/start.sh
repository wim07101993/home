#!/bin/sh
# Turns the Storage Box password into an rclone credential, then hands over.
#
# THIS FILE IS PUBLIC. The password is read from a mounted file.
#
# WHY THIS EXISTS AT ALL -- restic's SFTP backend cannot use a password. It
# shells out to ssh and offers no way to supply one, by design:
#
#   https://github.com/restic/restic/issues/448
#
# Key auth is the alternative and it is not available here. Storage Box SSH
# keys are a BOX-LEVEL attribute, and modules/hetzner/storage-box.tf keeps
# `ssh_keys` in ignore_changes because provider v1.58.0 made it
# replacement-forcing -- setting it would destroy the box holding every backup.
# hcloud_storage_box_subaccount has no ssh_keys attribute at all (verified
# against the provider schema, 2026-09-26).
#
# So restic reaches the box through rclone, which does support password auth
# and ships in this image. rclone stores passwords OBSCURED, and obscuring is
# not something tofu can compute -- hence these two lines rather than a plain
# env entry. Everything else about the remote is declared in the container's
# env, where it is visible in a diff.
#
# `exec` so /backrest keeps PID 1's signal handling via tini. Without it a
# `docker stop` would be delivered to this shell and the backup would not
# shut down cleanly.
set -eu

export RCLONE_CONFIG_STORAGEBOX_PASS="$(rclone obscure "$(cat /run/secrets/sftp_password)")"

exec /backrest
