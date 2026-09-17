# Organisations are NOT managed here, and that is the central decision of this
# whole rebuild.
#
# In zitadel, OIDC `sub` is the user id, and users belong to the ORG, not to a
# project. Verified 2026-09-17: memos stores that sub as the account's
# username. Recreating users would therefore hand every family member a fresh,
# empty memos account -- and the same class of breakage in immich, filebrowser
# and kitchen-owl, silently.
#
# So: orgs and users are left exactly as they are. Only projects, roles,
# applications and user grants are rebuilt. Nothing a user's identity depends
# on is touched, which is also why passkeys, passwords and MFA survive.
#
# Ids are literals rather than resources or data sources on purpose: there is
# nothing to read and nothing to manage, and a literal cannot accidentally
# propose a change to an org holding every account you have.

locals {
  # Instance-owned. Holds the ZITADEL project, its Management/Admin/Auth APIs
  # and the Console. Never ours to touch.
  org_zitadel = "340576542272847877"

  org_home = "342055441280270340"

  # `dev` (364673665767309316) is being REMOVED, not rebuilt -- it held a
  # duplicate score project whose apps pointed at localhost. Deleting an org is
  # not something tofu should do to a thing it does not manage, so it goes by
  # hand in the console once nothing references it.
}
