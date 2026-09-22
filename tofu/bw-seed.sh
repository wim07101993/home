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

# The full set. Order is display order in Bitwarden.
#
# The first nine are read by env.sh. The last three are NOT -- they are adopted
# into tofu state as random_password, and live here only as the out-of-band copy
# you would need to rebuild state from nothing.
VARS=(
  HCLOUD_TOKEN
  TOFU_STATE_DB_PASSWORD
  TF_VAR_state_passphrase
  TF_VAR_pg_superuser_password
  TF_VAR_pg_superuser_password_mindy
  TF_VAR_zitadel_pat
  TF_VAR_zitadel_masterkey
  TF_VAR_kopia_repository_password
  TF_VAR_mailgun_api_key
  TF_VAR_storage_box_password
  TF_VAR_immich_db_password
  TF_VAR_kopia_sftp_password
)

describe() {
  case "$1" in
    HCLOUD_TOKEN)                       echo "Hetzner Cloud API token" ;;
    TOFU_STATE_DB_PASSWORD)             echo "postgres role tofu_state, the STATE BACKEND" ;;
    TF_VAR_state_passphrase)            echo "state encryption passphrase, 16+ chars" ;;
    TF_VAR_pg_superuser_password)       echo "postgres superuser on bumba" ;;
    TF_VAR_pg_superuser_password_mindy) echo "postgres superuser on mindy (different value)" ;;
    TF_VAR_zitadel_pat)                 echo "PAT for the terraform service user" ;;
    TF_VAR_zitadel_masterkey)           echo "zitadel masterkey, 32 chars -- IRREPLACEABLE" ;;
    TF_VAR_kopia_repository_password)   echo "encrypts the backups -- lost = unreadable" ;;
    TF_VAR_mailgun_api_key)             echo "Mailgun API key" ;;
    TF_VAR_storage_box_password)        echo "Storage Box snow-white, MAIN account" ;;
    TF_VAR_immich_db_password)          echo "immich postgres (adopted into state)" ;;
    TF_VAR_kopia_sftp_password)         echo "Storage Box sub-account (adopted into state)" ;;
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
    TF_VAR_storage_box_password) echo "module.hetzner|storage_box" ;;
    TF_VAR_kopia_sftp_password)  echo "module.hetzner|storage_box_sftp" ;;
    TF_VAR_immich_db_password)   echo "module.immich|db" ;;
    TF_VAR_zitadel_masterkey)    echo "module.zitadel_server|masterkey" ;;
    *) echo "" ;;
  esac
}

_state_json=""
from_state() {   # from_state VARNAME
  local a m n
  a="$(state_addr "$1")"; [ -n "$a" ] || return 1
  m="${a%|*}"; n="${a#*|}"
  if [ -z "$_state_json" ]; then
    _state_json="$(tofu state pull 2>/dev/null)" || return 1
  fi
  printf '%s' "$_state_json" \
    | jq -r --arg m "$m" --arg n "$n" \
        '.resources[]? | select(.module==$m and .type=="random_password" and .name==$n)
         | .instances[0].attributes.result // empty' 2>/dev/null | grep . || return 1
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

  # 3. whatever the item already holds, so a skipped prompt keeps its value.
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
