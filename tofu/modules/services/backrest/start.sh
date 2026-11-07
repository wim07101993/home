#!/bin/sh
set -eu

export RCLONE_CONFIG_STORAGEBOX_PASS="$(rclone obscure - < /run/secrets/sftp_password)"

exec /backrest
