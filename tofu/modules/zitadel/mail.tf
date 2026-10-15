resource "random_password" "smtp" {
  length = 32

  # SASL PLAIN, and the value is written into zitadel's config. Alphanumeric
  # avoids a class of quoting bugs for no real loss of entropy at this length.
  special = false
}

resource "mailgun_domain_credential" "smtp" {
  domain = var.mail_domain

  # `auth`, and LOAD-BEARING. ./smtp.tf sends as auth@mail.wvl.app and its
  # `user` is derived from this login, so changing it changes the SMTP username
  # -- an update that the defect in that file makes effectively unappliable.
  login    = "auth"
  password = random_password.smtp.result
  region   = "eu" # must match the SMTP host in ./smtp.tf
}
