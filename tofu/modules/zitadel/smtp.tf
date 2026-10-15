resource "zitadel_email_provider_smtp" "this" {
  description = "mailgun"
  host = "smtp.eu.mailgun.org:587"
  tls  = true
  user     = "${mailgun_domain_credential.smtp.login}@${var.mail_domain}"
  password = random_password.smtp.result

  sender_address   = "auth@mail.wvl.app"
  sender_name      = "auth@mail.wvl.app"
  reply_to_address = "wim@wvl.app"
}
