resource "random_password" "smtp" {
  length = 32

  # Mailgun's SMTP password goes through SASL PLAIN and ends up interpolated
  # into config.yaml. Alphanumeric avoids a class of quoting bugs for no real
  # loss of entropy at this length.
  special = false
}

resource "mailgun_domain_credential" "smtp" {
  domain   = var.mail_domain
  login    = "gatus"
  password = random_password.smtp.result
  region   = var.mail_region
}
