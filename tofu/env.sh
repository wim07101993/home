#!/usr/bin/env bash
#
# Source this, do not execute it:   . ./env.sh
#
# Sets everything tofu needs. Each value is taken, in order, from the
# environment, from a tofu-loaded tfvars file, or -- failing both -- by
# prompting. Nothing here depends on a particular secret manager, and no secret
# is stored in this file, which is why it is safe in a public repo.
#
# TO STOP BEING PROMPTED: copy secrets.auto.tfvars.example to
# secrets.auto.tfvars and fill it in. That file is gitignored (`*.tfvars`), tofu
# loads it with no flag, and this script then skips those prompts. Two values
# cannot live there and must stay environment variables: TF_VAR_state_passphrase
# (read by the `encryption` block, evaluated before variables are loaded) and
# TOFU_STATE_DB_PASSWORD / PG_CONN_STR (backend config, not a tofu variable at
# all). HCLOUD_TOKEN is read by the provider from the environment.
#
# Non-interactive (CI, a wrapper, a systemd unit) -- export them beforehand:
#
#   HCLOUD_TOKEN                  Hetzner Cloud API token
#   TF_VAR_state_passphrase       state encryption passphrase, 16+ chars
#   TF_VAR_storage_box_password   Storage Box (snow-white) password
#   TF_VAR_pg_superuser_password        postgres superuser password on bumba
#   TF_VAR_pg_superuser_password_mindy  ... and on mindy (a different value)
#   TF_VAR_zitadel_pat            PAT for the `terraform` service user
#   TF_VAR_mailgun_api_key        Mailgun API key (mints SMTP credentials)
#   TF_VAR_zitadel_masterkey      Zitadel masterkey, 32 chars -- IRREPLACEABLE
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

# Where this script lives, so the *.auto.tfvars lookup below does not depend on
# the caller's working directory.
_tofu_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# True if a tfvars file tofu loads automatically already defines this variable.
#
# `*.auto.tfvars` and `terraform.tfvars` are read by tofu with no flag, so a
# value there makes prompting for it pointless -- and worse than pointless,
# because tfvars takes precedence over TF_VAR_ and the typed answer would be
# silently discarded.
#
# Deliberately NOT applied to TF_VAR_state_passphrase: it feeds the `encryption`
# block, which is evaluated earlier than ordinary variable loading. Treating it
# as satisfiable from a file risks an init that cannot decrypt, so it stays an
# environment variable regardless of what is in tfvars.
_tofu_has_tfvar() {   # _tofu_has_tfvar TF_VAR_foo
  local _n=${1#TF_VAR_}
  [ "$_n" = "$1" ] && return 1                  # not a TF_VAR_, not from tfvars
  [ "$1" = "TF_VAR_state_passphrase" ] && return 1
  # The value must be non-empty. Matching the NAME alone would treat a
  # half-filled `secrets.auto.tfvars` -- copied from the .example and not yet
  # completed -- as answered, and hand tofu an empty password with no prompt
  # and no error. Accepts "something" or a bare token; rejects "".
  grep -qsE "^[[:space:]]*${_n}[[:space:]]*=[[:space:]]*(\"[^\"]+\"|[^\"[:space:]]+)" \
    "$_tofu_dir"/*.auto.tfvars "$_tofu_dir"/terraform.tfvars 2>/dev/null
}

_tofu_need() {   # _tofu_need VARNAME "human description"
  local _var="$1" _desc="$2" _val=""
  [ -n "${!_var:-}" ] && return 0
  _tofu_has_tfvar "$_var" && return 0
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

if [ -z "${MINDY_ADDR:-}" ]; then
  : "${MINDY_TS_HOST:=mindy}"
  MINDY_ADDR="$(tailscale ip -4 "$MINDY_TS_HOST" 2>/dev/null)" || MINDY_ADDR=""
  [ -n "$MINDY_ADDR" ] || {
    echo "env.sh: cannot resolve '$MINDY_TS_HOST' on the tailnet." >&2
    echo "        Check 'tailscale status', or set MINDY_TS_HOST / MINDY_ADDR." >&2
    return 1
  }
fi
export MINDY_ADDR
export TF_VAR_mindy_addr="$MINDY_ADDR"


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
_tofu_need TF_VAR_pg_superuser_password_mindy "postgres SUPERUSER password on MINDY" || return 1
_tofu_need TF_VAR_immich_db_password "immich's existing postgres password" || return 1

# Kopia. Two credentials: the repository password (encrypts the backups) and
# the Storage Box SUB-account password. Neither is TF_VAR_storage_box_password.
_tofu_need TF_VAR_kopia_repository_password "kopia repository password" || return 1
_tofu_need TF_VAR_kopia_sftp_password "kopia Storage Box sub-account password" || return 1

# Zitadel's masterkey -- 32 bytes, and the one value in this estate that cannot
# be regenerated. Prefer secrets.auto.tfvars over typing it; see
# modules/services/zitadel/variables.tf.
_tofu_need TF_VAR_zitadel_masterkey "Zitadel masterkey (32 chars)" || return 1

# Mailgun. One key, not one password per service: tofu creates gatus's SMTP
# credential itself (modules/mailgun), so there is no longer an SMTP password
# to type. Scope the key in the Mailgun console -- it can manage the account.
_tofu_need TF_VAR_mailgun_api_key "Mailgun API key" || return 1

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

unset -f _tofu_need _tofu_has_tfvar
unset _tofu_dir
echo "env.sh: environment set (bumba ${BUMBA_ADDR}, mindy ${MINDY_ADDR})"
