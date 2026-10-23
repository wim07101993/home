resource "random_password" "smtp" {
  length = 32

  # SASL PLAIN, passed through the container environment into postfix's
  # sasl_passwd. Alphanumeric avoids a class of quoting bugs for no real loss of
  # entropy at this length.
  special = false
}

resource "mailgun_domain_credential" "smtp" {
  domain   = var.mail_domain
  login    = var.login
  password = random_password.smtp.result
  region   = "eu" # must match RELAYHOST in ./main.tf
}
