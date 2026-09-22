resource "random_password" "gatus" {
  length = 32

  # Mailgun's SMTP password goes through SASL PLAIN and ends up pasted into
  # config files. Alphanumeric avoids a class of quoting bugs for no real loss
  # of entropy at this length.
  special = false
}

resource "mailgun_domain_credential" "gatus" {
  domain = var.domain
  login    = "gatus"
  password = random_password.gatus.result
  region   = var.region
}

resource "random_password" "auth" {
  length  = 32
  special = false
}

resource "mailgun_domain_credential" "auth" {
  domain   = var.domain
  login    = "auth"
  password = random_password.auth.result
  region   = var.region
}

output "auth_smtp_username" {
  description = "Full SMTP login for zitadel -- auth@<domain>."
  value       = "${mailgun_domain_credential.auth.login}@${var.domain}"
}

output "auth_smtp_password" {
  value     = random_password.auth.result
  sensitive = true
}

output "gatus_smtp_username" {
  description = "Full SMTP login for gatus -- gatus@<domain>."
  value       = "${mailgun_domain_credential.gatus.login}@${var.domain}"
}

output "gatus_smtp_password" {
  value     = random_password.gatus.result
  sensitive = true
}
