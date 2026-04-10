resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "random_password" "memo_db_password" {
  length  = 32
  special = false
}

resource "random_password" "zitadel_user_password" {
  length  = 32
  special = false
}

resource "random_password" "zitadel_root_password" {
  length  = 32
  special = false
}

resource "random_password" "zitadel_masterkey" {
  length  = 32
  special = false
}
