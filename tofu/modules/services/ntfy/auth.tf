# The phone app's login.
resource "random_password" "wim" {
  length  = 32
  special = false
}

resource "random_password" "gatus" {
  length  = 32
  special = false
}

resource "random_password" "gatus_token" {
  length  = 29
  special = false
  upper   = false
}
