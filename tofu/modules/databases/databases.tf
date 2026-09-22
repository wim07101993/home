# =========================================================================
# bumba
# =========================================================================

# --- zitadel -------------------------------------------------------------

resource "random_password" "zitadel_user" {
  length  = 32
  special = false
}

resource "postgresql_role" "zitadel_user" {
  provider = postgresql.bumba
  name     = "zitadel_user"
  login    = true
  inherit  = false
  password = random_password.zitadel_user.result
}

resource "random_password" "zitadel_root" {
  length  = 32
  special = false
}

resource "postgresql_role" "zitadel_root" {
  provider  = postgresql.bumba
  name      = "zitadel_root"
  login     = true
  inherit   = false
  superuser = true
  password  = random_password.zitadel_root.result
}

resource "postgresql_database" "zitadel" {
  provider = postgresql.bumba
  name     = "zitadel"
  owner    = postgresql_role.zitadel_root.name

  lifecycle {
    prevent_destroy = true
  }
}

# =========================================================================
# mindy
# =========================================================================

# --- score ---------------------------------------------------------------

resource "random_password" "score_api" {
  length  = 32
  special = false
}

resource "postgresql_role" "score_api" {
  name     = "score_api"
  login    = true
  password = random_password.score_api.result
  inherit = false
}

resource "postgresql_database" "score" {
  name  = "score"
  owner = postgresql_role.score_api.name

  lifecycle {
    prevent_destroy = true
  }
}

# --- kitchen-owl ---------------------------------------------------------

resource "random_password" "kitchenowl" {
  length  = 32
  special = false
}

resource "postgresql_role" "kitchenowl" {
  name     = "kitchenowl"
  login    = true
  password = random_password.kitchenowl.result
  inherit = false
}

resource "postgresql_database" "kitchenowl" {
  name  = "kitchenowl"
  owner = postgresql_role.kitchenowl.name

  lifecycle {
    prevent_destroy = true
  }
}

# --- memos ---------------------------------------------------------------

resource "random_password" "memos" {
  length  = 32
  special = false
}

resource "postgresql_role" "memos" {
  name     = "memos"
  login    = true
  password = random_password.memos.result
  inherit = false
}

resource "postgresql_database" "memos" {
  name  = "memos"
  owner = postgresql_role.memos.name

  lifecycle {
    prevent_destroy = true
  }
}
