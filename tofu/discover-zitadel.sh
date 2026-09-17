#!/usr/bin/env bash
#
# Read-only. Lists what exists in Zitadel -- orgs, projects, applications,
# actions -- with the ids that `import` blocks need.
#
#   ZITADEL_PAT=... ./discover-zitadel.sh
#
# Nothing here touches tofu, state, or the provider. It is plain HTTP against
# the Zitadel APIs, so it works before any of the wiring exists.
#
# The PAT belongs to a machine user you create for this -- see README.md,
# "Adopting Zitadel". Do NOT reuse /docker-volumes/zitadel/login-client.pat:
# that one belongs to the login UI, is scoped IAM_LOGIN_CLIENT, and coupling
# terraform to it means rotating one breaks the other.

set -euo pipefail
for c in curl jq; do
  command -v "$c" >/dev/null 2>&1 || { echo "missing '$c'" >&2; exit 1; }
done

DOMAIN="${ZITADEL_DOMAIN:-auth.wvl.app}"
: "${ZITADEL_PAT:?set ZITADEL_PAT -- see README.md, \"Adopting Zitadel\"}"

api() { # api METHOD PATH [BODY] [ORG_ID]
  local method="$1" path="$2" body="${3:-}" org="${4:-}"
  local -a args=(-sS -X "$method" "https://${DOMAIN}${path}"
                 -H "Authorization: Bearer ${ZITADEL_PAT}"
                 -H 'Content-Type: application/json')
  [ -n "$org" ]  && args+=(-H "x-zitadel-orgid: ${org}")
  [ -n "$body" ] && args+=(-d "$body")
  curl "${args[@]}"
}

echo "=== token identity ==="
if ! api GET /auth/v1/users/me | jq -e '.user' >/dev/null 2>&1; then
  echo "the PAT was rejected, or the user has no permissions." >&2
  api GET /auth/v1/users/me | jq . >&2 || true
  exit 1
fi
api GET /auth/v1/users/me \
  | jq -r '.user | "  user   \(.userName)\n  id     \(.id)\n  org    \(.details.resourceOwner)"'

echo
echo "=== organisations ==="
ORGS_JSON="$(api POST /admin/v1/orgs/_search '{"query":{"limit":1000}}' || true)"
if ! echo "$ORGS_JSON" | jq -e '.result' >/dev/null 2>&1; then
  echo "  (cannot list orgs -- the machine user probably lacks IAM_OWNER;" >&2
  echo "   falling back to its own org only)" >&2
  ORGS_JSON="$(api GET /management/v1/orgs/me | jq '{result:[.org]}')"
fi
echo "$ORGS_JSON" | jq -r '.result[] | "  \(.id)  \(.name)  [\(.state)]"'

echo
echo "=== projects and applications, per org ==="
for org in $(echo "$ORGS_JSON" | jq -r '.result[].id'); do
  org_name="$(echo "$ORGS_JSON" | jq -r --arg i "$org" '.result[]|select(.id==$i)|.name')"
  echo
  echo "  org ${org}  ${org_name}"

  projects="$(api POST /management/v1/projects/_search '{"query":{"limit":1000}}' "$org")"
  echo "$projects" | jq -e '.result' >/dev/null 2>&1 || { echo "    (no projects)"; continue; }

  for proj in $(echo "$projects" | jq -r '.result[]?.id'); do
    proj_name="$(echo "$projects" | jq -r --arg i "$proj" '.result[]|select(.id==$i)|.name')"
    echo "    project ${proj}  ${proj_name}"

    apps="$(api POST "/management/v1/projects/${proj}/apps/_search" '{"query":{"limit":1000}}' "$org")"
    echo "$apps" | jq -r '
      .result[]? |
      "      app \(.id)  \(.name)  " +
        (if   .oidcConfig then "oidc/\(.oidcConfig.appType // "?")"
         elif .apiConfig  then "api/\(.apiConfig.authMethodType // "?")"
         elif .samlConfig then "saml"
         else "?" end)' 2>/dev/null || echo "      (no apps)"
  done

  echo "    --- actions ---"
  api POST /management/v1/actions/_search '{"query":{"limit":1000}}' "$org" \
    | jq -r '.result[]? | "    action \(.id)  \(.name)  [\(.state)]"' 2>/dev/null || true
done

cat <<'NEXT'

==> These ids are what the import blocks need. Import ids in the zitadel
    provider are usually composite (`<org_id>_<project_id>_<app_id>` for an
    application, for example) and differ per resource type -- check the
    provider docs per resource rather than assuming a bare id.

    Paste this output and the import blocks can be written from it.

NEXT
