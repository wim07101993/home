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
# The ORGS THEMSELVES are adopted (2026-09-22); their CONTENTS still are not.
# Users, grants, passkeys and MFA remain untouched -- only the org object is in
# state, so that every resource in this estate is managed rather than some being
# literals for historical reasons.
#
# `prevent_destroy` on both, for the reason in the paragraph above: destroying
# `Home` would take every account with it. That is the same protection the
# databases carry, and the same argument -- "tofu could delete it" is true of
# everything here, and is answered by prevent_destroy rather than by refusing to
# manage the resource.
#
# `admins` is deliberately unset. It is Optional, and setting it would put tofu
# in charge of who owns the org -- which IS org contents, and is exactly what
# this module does not touch.

# Instance-owned. Holds the ZITADEL project, its Management/Admin/Auth APIs and
# the Console. Adopted so it is visible in state, never modified.
resource "zitadel_org" "zitadel" {
  name = "Zitadel"

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_org" "home" {
  name = "Home"

  lifecycle {
    prevent_destroy = true
  }
}

# `dev` (364673665767309316) is being REMOVED, not rebuilt -- it held a duplicate
# score project whose apps pointed at localhost. Deleting an org is not something
# tofu should do to a thing it does not manage, so it goes by hand in the console
# once nothing references it. It is deliberately NOT adopted above: a resource
# whose purpose is to disappear does not belong in state.
