#!/usr/bin/env bash
#
# Source this, do not execute it:   . ./env.sh
#
# Sets everything tofu needs. Each value is taken from the environment if it is
# already set, and prompted for otherwise. Nothing here depends on a particular
# secret manager, and no secret is stored in this file -- which is why it is
# safe in a public repo.
#
# Non-interactive (CI, a wrapper, a systemd unit) -- export them beforehand:
#
#   HCLOUD_TOKEN                  Hetzner Cloud API token
#   TF_VAR_state_passphrase       state encryption passphrase, 16+ chars
#   TF_VAR_storage_box_password   Storage Box (snow-white) password
#   TF_VAR_pg_superuser_password  postgres superuser password on bumba
#   TF_VAR_zitadel_pat            PAT for the `terraform` service user
#   TOFU_STATE_DB_PASSWORD        the tofu_state role, for the BACKEND
#   PG_CONN_STR                   overrides the last one entirely
#   BUMBA_ADDR                    skips the `tailscale ip` lookup
#
# Note there are TWO postgres credentials and they are not the same:
#
#   backend   connects as tofu_state -- owns nothing but its own database
#   provider  connects as postgres   -- superuser, creates roles and databases
#
# Keeping them apart is what stops an apply that goes wrong from also
# destroying the record of what it did.
#
# If you keep these in a vault, that is a line in your own shell rc, not a
# dependency of this repo. For example:
#
#   export TF_VAR_state_passphrase="$(rbw get 'OpenTofu state')"   # or bw, pass, ...

_tofu_need() {   # _tofu_need VARNAME "human description"
  local _var="$1" _desc="$2" _val=""
  [ -n "${!_var:-}" ] && return 0
  # -r /dev/tty is not enough: the file can exist and still fail to open when
  # there is no controlling terminal. Try it for real.
  if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    echo "env.sh: $_var is unset and there is no terminal to prompt on." >&2
    echo "        export $_var=... before sourcing this." >&2
    return 1
  fi
  printf '%s (%s): ' "$_desc" "$_var" >&3
  IFS= read -rs _val < /dev/tty
  printf '\n' >&3
  exec 3>&-
  [ -n "$_val" ] || { echo "env.sh: empty value for $_var" >&2; return 1; }
  export "$_var=$_val"
}

# bumba's tailnet address -- used by the postgresql provider AND the backend.
# Never the public IP: both connections are unencrypted at the postgres layer
# and rely on WireGuard for transport security.
if [ -z "${BUMBA_ADDR:-}" ]; then
  : "${BUMBA_TS_HOST:=bumba}"   # `tailscale status` lists the device names
  command -v tailscale >/dev/null 2>&1 || {
    echo "env.sh: no 'tailscale' command. Set BUMBA_ADDR." >&2
    return 1
  }
  BUMBA_ADDR="$(tailscale ip -4 "$BUMBA_TS_HOST" 2>/dev/null)" || BUMBA_ADDR=""
  [ -n "$BUMBA_ADDR" ] || {
    echo "env.sh: cannot resolve '$BUMBA_TS_HOST' on the tailnet." >&2
    echo "        Check 'tailscale status', or set BUMBA_TS_HOST / BUMBA_ADDR." >&2
    return 1
  }
fi
export BUMBA_ADDR
export TF_VAR_bumba_addr="$BUMBA_ADDR"


# A read-only token cannot create a database, so this module can no longer run
# read-only indefinitely -- see the note in providers.tf. Use one anyway for
# anything that is pure adoption or a plan.
_tofu_need HCLOUD_TOKEN "Hetzner Cloud API token" || return 1
_tofu_need TF_VAR_state_passphrase "OpenTofu state encryption passphrase" || return 1

# hcloud_storage_box takes `password` as a REQUIRED argument and the Cloud API
# never returns it, so config generation cannot fill it in and tofu cannot
# verify it. storage-box.tf ignores changes to it for that reason -- but it
# still has to be set. Reset it in the Cloud Console if it is not to hand.
_tofu_need TF_VAR_storage_box_password "Storage Box (snow-white) password" || return 1

_tofu_need TF_VAR_pg_superuser_password "postgres SUPERUSER password on bumba" || return 1

# PAT for the `terraform` service user in Zitadel (IAM_OWNER). Created by hand
# in the console -- modules/zitadel/README.md.
_tofu_need TF_VAR_zitadel_pat "Zitadel PAT for the terraform service user" || return 1

if [ -z "${PG_CONN_STR:-}" ]; then
  _tofu_need TOFU_STATE_DB_PASSWORD "postgres password for role tofu_state (backend)" || return 1

  # libpq keyword/value form, not a postgres:// URI. A URI would need the
  # password percent-encoded, and an unescaped '@' or '/' in it silently
  # produces a connection string that points somewhere else. Both psql and the
  # pg backend accept this form.
  _pw=${TOFU_STATE_DB_PASSWORD//\\/\\\\}   # \ -> \\
  _pw=${_pw//\'/\\\'}                      # ' -> \'
  export PG_CONN_STR="host=${BUMBA_ADDR} port=5432 dbname=tofu_state user=tofu_state password='${_pw}' sslmode=disable"
  unset _pw
fi

unset -f _tofu_need
echo "env.sh: environment set (bumba ${BUMBA_ADDR})"
