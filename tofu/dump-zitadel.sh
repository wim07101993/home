#!/usr/bin/env bash
#
# Read-only. Dumps the FULL definition of every project, role, application and
# user grant to ./zitadel-dump/, so the tofu rebuild can be checked against
# what exists rather than against memory.
#
#   ZITADEL_PAT=... ./dump-zitadel.sh
#
# discover-zitadel.sh prints an inventory; this prints the configuration --
# redirect URIs, grant types, auth methods, roles, grants. That is what
# "make sure the config is the same" needs.
#
# The dump is gitignored: app definitions are not secret, but client secrets
# can appear in API responses and this repo is public.

set -euo pipefail
for c in curl jq; do
  command -v "$c" >/dev/null 2>&1 || { echo "missing '$c'" >&2; exit 1; }
done

DOMAIN="${ZITADEL_DOMAIN:-auth.wvl.app}"
OUT="${OUT:-./zitadel-dump}"
: "${ZITADEL_PAT:?set ZITADEL_PAT}"

api() { # api METHOD PATH BODY ORG
  curl -sS -X "$1" "https://${DOMAIN}$2" \
    -H "Authorization: Bearer ${ZITADEL_PAT}" \
    -H 'Content-Type: application/json' \
    ${4:+-H "x-zitadel-orgid: $4"} \
    ${3:+-d "$3"}
}

mkdir -p "$OUT"
echo "==> $OUT"

orgs="$(api POST /admin/v1/orgs/_search '{"query":{"limit":1000}}')"
echo "$orgs" | jq '.result' > "$OUT/orgs.json"

for org in $(echo "$orgs" | jq -r '.result[].id'); do
  name="$(echo "$orgs" | jq -r --arg i "$org" '.result[]|select(.id==$i)|.name')"

  # The instance's own org holds the ZITADEL project and its APIs. Not ours.
  if [ "$name" = "Zitadel" ]; then
    echo "  skip org $name ($org) -- instance-owned"
    continue
  fi

  d="$OUT/org-$org"
  mkdir -p "$d"
  echo "  org $name ($org)"

  api POST /management/v1/projects/_search '{"query":{"limit":1000}}' "$org" \
    | jq '.result' > "$d/projects.json"

  for proj in $(jq -r '.[]?.id' "$d/projects.json"); do
    pname="$(jq -r --arg i "$proj" '.[]|select(.id==$i)|.name' "$d/projects.json")"
    pd="$d/project-$proj"
    mkdir -p "$pd"
    echo "    project $pname ($proj)"

    api POST "/management/v1/projects/${proj}/apps/_search"  '{"query":{"limit":1000}}' "$org" | jq '.result' > "$pd/apps.json"
    api POST "/management/v1/projects/${proj}/roles/_search" '{"query":{"limit":1000}}' "$org" | jq '.result' > "$pd/roles.json"
    api POST "/management/v1/projects/${proj}/grants/_search" '{"query":{"limit":1000}}' "$org" | jq '.result' > "$pd/project-grants.json" 2>/dev/null || true
  done

  # User grants are per-org, not per-project. These are what die with the old
  # projects and have to be recreated -- the one piece of user-adjacent state
  # the rebuild touches.
  api POST /management/v1/users/grants/_search '{"query":{"limit":1000}}' "$org" \
    | jq '.result' > "$d/user-grants.json"
done

echo
echo "==> summary"
find "$OUT" -name apps.json | while read -r f; do
  jq -r --arg f "$f" '.[]? | "  \($f|split("/")[-2])  \(.name)"' "$f"
done
echo
echo "  applications : $(cat $(find "$OUT" -name apps.json) | jq -s 'add|length')"
echo "  user grants  : $(cat $(find "$OUT" -name user-grants.json) | jq -s 'add|length')"
