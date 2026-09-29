#!/usr/bin/env bash
#
# Write every secret this repo needs into ONE Bitwarden item, as hidden custom
# fields named after the variables.
#
#   bash bw-seed.sh
#
# Run it, not source it. Requires an unlocked vault:
#
#   export BW_SESSION="$(bw unlock --raw)"
#
# Values are taken from the environment when already set (so sourcing env.sh
# first seeds them without retyping), otherwise prompted for. An empty answer
# SKIPS the field rather than storing "" -- an empty secret that looks present
# is worse than an absent one, which is the failure that put an empty password
# into tofu state on 2026-09-19.
#
# Re-running is safe: an existing item is updated, and fields you skip keep
# their current values.
set -uo pipefail

ITEM_NAME="${TOFU_BW_ITEM:-tofu home}"

# Where this script lives, so the tfvars lookup below does not depend on the
# caller's working directory -- same reasoning as _tofu_dir in env.sh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The full set. Order is display order in Bitwarden.
#
# TWO KINDS, and the prefix says which:
#
#   TF_VAR_*   a real tofu INPUT. env.sh exports it and tofu reads it. The name
#              must match a `variable` block in the root exactly -- rename one
#              without the other and tofu silently falls back to prompting.
#   BARE NAME  generated or adopted INTO tofu state. Nothing reads it as an
#              env var; the vault copy is the out-of-band one you would need to
#              rebuild state from nothing.
#
# Four entries carried a TF_VAR_ prefix without a matching root variable until
# 2026-09-28 -- exporting them did nothing. They are bare names now.
#
# Each value is resolved in order: tofu state, the environment, a tfvars file,
# the field already on the item, and only then a prompt. The tfvars step exists
# because env.sh deliberately does not export those -- see from_tfvars below.
VARS=(
  HCLOUD_TOKEN
  TOFU_STATE_DB_PASSWORD
  TF_VAR_state_passphrase
  TF_VAR_bumba_pg_superuser_password
  TF_VAR_mindy_pg_superuser_password
  TF_VAR_immich_pg_superuser_password
  ZITADEL_MASTERKEY
  BACKREST_REPOSITORY_PASSWORD
  TF_VAR_mailgun_api_key
  STORAGE_BOX_PASSWORD
  IMMICH_DB_PASSWORD
  KOPIA_REPOSITORY_PASSWORD
  KOPIA_SFTP_PASSWORD
  BACKREST_MINDY_PASSWORD
  BACKREST_SAMSON_PASSWORD
)

describe() {
  case "$1" in
    HCLOUD_TOKEN)                       echo "Hetzner Cloud API token" ;;
    TOFU_STATE_DB_PASSWORD)             echo "postgres role tofu_state, the STATE BACKEND" ;;
    TF_VAR_state_passphrase)            echo "state encryption passphrase, 16+ chars" ;;
    TF_VAR_bumba_pg_superuser_password)       echo "postgres superuser on bumba" ;;
    TF_VAR_mindy_pg_superuser_password) echo "postgres superuser on mindy (different value)" ;;
    TF_VAR_immich_pg_superuser_password) echo "postgres superuser on immich's own postgres, mindy:5434" ;;
    ZITADEL_MASTERKEY)           echo "zitadel masterkey, 32 chars -- IRREPLACEABLE" ;;
    BACKREST_REPOSITORY_PASSWORD)       echo "encrypts the RESTIC repositories (generated, in state) -- lost = unreadable" ;;
    TF_VAR_mailgun_api_key)             echo "Mailgun API key" ;;
    STORAGE_BOX_PASSWORD)        echo "Storage Box snow-white, MAIN account" ;;
    IMMICH_DB_PASSWORD)          echo "immich's APP role (generated, in state)" ;;
    KOPIA_REPOSITORY_PASSWORD)   echo "decrypts the RETIRED kopia repository -- lost = those backups unreadable" ;;
    KOPIA_SFTP_PASSWORD)         echo "Storage Box sub-account holding the RETIRED kopia repository" ;;
    BACKREST_MINDY_PASSWORD)            echo "backrest web UI on mindy, user wim (generated, in state)" ;;
    BACKREST_SAMSON_PASSWORD)           echo "backrest web UI on samson, user wim (generated, in state)" ;;
    *)                                  echo "" ;;
  esac
}

# VARNAME -> the tofu state address holding it, for secrets tofu GENERATES or
# has adopted. For these, state is AUTHORITATIVE: it is read before the existing
# vault field, so a rotation propagates here instead of the stale copy winning.
#
# Anything not listed is the other way round -- the vault is the source of truth
# and state never holds it.
state_addr() {
  case "$1" in
    STORAGE_BOX_PASSWORD) echo "module.hetzner|storage_box" ;;
    KOPIA_SFTP_PASSWORD)  echo "module.hetzner|storage_box_sftp" ;;
    IMMICH_DB_PASSWORD)   echo "module.immich|db" ;;
    # ROOT-module resource, so the module half is empty -- from_state splits on
    # the pipe and matches `.module // ""`. This is the one secret here that
    # tofu generates and cannot reset, so the vault copy is the whole point.
    BACKREST_REPOSITORY_PASSWORD) echo "|backrest_repository" ;;
    BACKREST_MINDY_PASSWORD)     echo "module.backrest_mindy|ui" ;;
    BACKREST_SAMSON_PASSWORD)    echo "module.backrest_samson|ui" ;;
    ZITADEL_MASTERKEY)    echo "module.zitadel_server|masterkey" ;;
    *) echo "" ;;
  esac
}

_state_json=""

# from_state_addr <module> <random_password name>. The lookup half of
# from_state below, callable without a VARNAME mapping -- used by LOGIN_ITEMS.
from_state_addr() {
  local m="$1" n="$2"
  if [ -z "$_state_json" ]; then
    _state_json="$(tofu state pull 2>/dev/null)" || return 1
  fi
  printf '%s' "$_state_json" \
    | jq -r --arg m "$m" --arg n "$n" \
        '.resources[]? | select((.module // "")==$m and .type=="random_password" and .name==$n)
         | .instances[0].attributes.result // empty' 2>/dev/null | grep . || return 1
}

from_state() {   # from_state VARNAME
  local a m n
  a="$(state_addr "$1")"; [ -n "$a" ] || return 1
  m="${a%|*}"; n="${a#*|}"
  if [ -z "$_state_json" ]; then
    _state_json="$(tofu state pull 2>/dev/null)" || return 1
  fi
  printf '%s' "$_state_json" \
    | jq -r --arg m "$m" --arg n "$n" \
        '.resources[]? | select((.module // "")==$m and .type=="random_password" and .name==$n)
         | .instances[0].attributes.result // empty' 2>/dev/null | grep . || return 1
}

# VARNAME -> the value a tfvars file already defines, if any.
#
# env.sh deliberately does NOT export these: a *.auto.tfvars entry beats a
# TF_VAR_ environment variable at apply time, so exporting one would be a
# value that looks authoritative and is not. That leaves them invisible to the
# environment, and a secret that lives only in a gitignored file on one laptop
# is the one most worth having a vault copy of.
#
# Same matcher as _tofu_has_tfvar in env.sh, and the same reason for demanding
# a non-empty value: a secrets.auto.tfvars copied from the .example and not yet
# filled in would otherwise seed the vault with "".
from_tfvars() {   # from_tfvars VARNAME
  local n="${1#TF_VAR_}"
  [ "$n" = "$1" ] && return 1
  sed -nE "s/^[[:space:]]*${n}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" \
    "$SCRIPT_DIR"/*.auto.tfvars "$SCRIPT_DIR"/terraform.tfvars 2>/dev/null \
    | head -1 | grep . || return 1
}

command -v bw >/dev/null 2>&1 || { echo "bw not installed" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not installed" >&2; exit 1; }
case "$(bw status 2>/dev/null)" in
  *'"status":"unlocked"'*) ;;
  *) echo 'vault is locked. export BW_SESSION="$(bw unlock --raw)"' >&2; exit 1 ;;
esac

# Existing item, if any. `bw get item` matches on exact name.
existing="$(bw get item "$ITEM_NAME" 2>/dev/null)" || existing=""
if [ -n "$existing" ]; then
  echo "updating existing item: $ITEM_NAME"
else
  echo "creating new item: $ITEM_NAME"
fi

fields='[]'
for v in "${VARS[@]}"; do
  cur=""
  src=""

  # 1. tofu state, for the secrets tofu owns. AUTHORITATIVE -- checked before
  #    the vault, so a rotation propagates instead of a stale copy winning.
  if [ -n "$(state_addr "$v")" ]; then
    cur="$(from_state "$v" || true)"
    [ -n "$cur" ] && src="tofu state"
  fi

  # 2. the environment, so sourcing env.sh first avoids retyping.
  if [ -z "$cur" ] && [ -n "${!v:-}" ]; then
    cur="${!v}"
    src="env"
  fi

  # 3. a tfvars file, which env.sh leaves out of the environment on purpose.
  #    Ahead of the vault because it is what tofu actually reads.
  if [ -z "$cur" ]; then
    cur="$(from_tfvars "$v" || true)"
    [ -n "$cur" ] && src="tfvars"
  fi

  # 4. whatever the item already holds, so a skipped prompt keeps its value.
  if [ -z "$cur" ] && [ -n "$existing" ]; then
    cur="$(printf '%s' "$existing" | jq -r --arg n "$v" '.fields[]? | select(.name==$n) | .value // empty')"
    [ -n "$cur" ] && src="vault"
  fi

  if [ -n "$cur" ]; then
    printf '  %-36s [%s]\n' "$v" "$src"
    val="$cur"
  else
    printf '  %s\n    %s\n    value (empty to skip): ' "$v" "$(describe "$v")"
    IFS= read -rs val < /dev/tty; printf '\n'
    [ -n "$val" ] || { printf '    skipped\n'; continue; }
  fi

  fields="$(jq -c --arg n "$v" --arg val "$val" '. + [{name:$n, value:$val, type:1}]' <<<"$fields")"
done

# --- separate LOGIN items -------------------------------------------------
#
# The item above holds everything as custom FIELDS on one entry with no URI, so
# Bitwarden can never offer to fill it. These are real login items -- username,
# password, and the address the service answers on -- so the browser extension
# recognises them.
#
# Only for credentials a PERSON types into a form. Everything else stays a
# field on the shared item: an API token that only tofu uses gains nothing from
# being autofillable, and a vault full of unfillable "logins" is how people
# stop trusting the ones that are real.
#
# name | username | uri | <state module>|<random_password name>
LOGIN_ITEMS=(
  "backrest (mindy)|wim|http://${MINDY_ADDR:-100.127.106.121}:9898|module.backrest_mindy|ui"
  "backrest (samson)|wim|http://${SAMSON_ADDR:-100.71.248.106}:9898|module.backrest_samson|ui"
)

login_notes="Generated by tofu; state is authoritative.
Re-run tofu/bw-seed.sh after a rotation -- editing this by hand will be
overwritten, and the value here will not change what the server accepts.
backrest is plain HTTP over the tailnet -- the transport is WireGuard."

for spec in "${LOGIN_ITEMS[@]}"; do
  IFS='|' read -r li_name li_user li_uri li_mod li_res <<<"$spec"

  # State is the only copy. No prompt fallback: a hand-typed value here would
  # be a login that looks right and does not work.
  li_pass="$(from_state_addr "$li_mod" "$li_res" || true)"
  if [ -z "$li_pass" ]; then
    printf '  %-36s [skipped -- not in state yet]\n' "$li_name"
    continue
  fi

  li_existing="$(bw get item "$li_name" 2>/dev/null)" || li_existing=""
  if [ -n "$li_existing" ]; then
    li_id="$(jq -r '.id' <<<"$li_existing")"
    jq -c --arg u "$li_user" --arg p "$li_pass" --arg uri "$li_uri" --arg n "$login_notes" \
       '.notes = $n
        | .login.username = $u
        | .login.password = $p
        | .login.uris = [{match: null, uri: $uri}]' <<<"$li_existing" \
      | bw encode | bw edit item "$li_id" >/dev/null || { echo "bw edit failed: $li_name" >&2; exit 1; }
    printf '  %-36s [updated]\n' "$li_name"
  else
    jq -nc --arg name "$li_name" --arg u "$li_user" --arg p "$li_pass" --arg uri "$li_uri" --arg n "$login_notes" '{
      organizationId: null, collectionIds: null, folderId: null,
      type: 1, name: $name, notes: $n, favorite: false,
      fields: [],
      login: { username: $u, password: $p, totp: null, uris: [{match: null, uri: $uri}] },
      reprompt: 0
    }' | bw encode | bw create item >/dev/null || { echo "bw create failed: $li_name" >&2; exit 1; }
    printf '  %-36s [created]\n' "$li_name"
  fi
done

notes="Every secret for github.com/wim07101993/home (tofu).
Field names are the EXACT environment variable names env.sh looks for.
Written by tofu/bw-seed.sh -- re-run it to add or change fields."

if [ -n "$existing" ]; then
  id="$(jq -r '.id' <<<"$existing")"
  jq -c --argjson f "$fields" --arg notes "$notes" \
     '.fields = $f | .notes = $notes' <<<"$existing" \
    | bw encode | bw edit item "$id" >/dev/null || { echo "bw edit failed" >&2; exit 1; }
  echo "updated $(jq 'length' <<<"$fields") field(s) on $ITEM_NAME"
else
  jq -nc --arg name "$ITEM_NAME" --argjson f "$fields" --arg notes "$notes" '{
    organizationId: null, collectionIds: null, folderId: null,
    type: 1, name: $name, notes: $notes, favorite: false,
    fields: $f,
    login: { username: null, password: null, totp: null, uris: [] },
    reprompt: 0
  }' | bw encode | bw create item >/dev/null || { echo "bw create failed" >&2; exit 1; }
  echo "created $ITEM_NAME with $(jq 'length' <<<"$fields") field(s)"
fi
