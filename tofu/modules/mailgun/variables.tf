variable "domain" {
  type        = string
  default     = "mail.wvl.app"
  description = "The Mailgun SENDING domain. Not wvl.app -- mail is sent from a subdomain."
}

variable "region" {
  type        = string
  default     = "eu"
  description = <<-EOT
    Mailgun region. The provider defaults to `us`; this account is EU.

    Getting it wrong is not a loud failure. The provider would talk to
    api.mailgun.net instead of api.eu.mailgun.net and create the credential in
    an account that is not this one, while postfix and gatus keep
    authenticating against smtp.eu.mailgun.org and failing.
  EOT
}
