# Where this module's own SMTP credential is minted -- see ./mail.tf. The
# credential is no longer passed in; this module owns it, because ./smtp.tf is
# the thing that authenticates with it.
#
# Only the domain and region are inputs, so the credential's login and the
# sender address in ./smtp.tf cannot drift apart.
variable "mail_domain" {
  type    = string
  default = "mail.wvl.app"
}

variable "mail_region" {
  type    = string
  default = "eu"
}
