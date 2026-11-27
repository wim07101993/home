resource "random_password" "smtp" {
  length = 32

  # Passed through the container environment into SASL PLAIN. Alphanumeric
  # avoids a class of quoting bugs for no real loss of entropy at this length.
  special = false
}

resource "mailgun_domain_credential" "smtp" {
  domain   = var.mail_domain
  login    = "databasus"
  password = random_password.smtp.result
  region   = "eu" # must match SMTP_HOST in ./main.tf
}
