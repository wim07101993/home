# Zitadel's outbound SMTP credential at Mailgun -- the one ./smtp.tf
# authenticates with for verification links, password resets and OTP codes.
#
# MOVED HERE from ../mailgun on 2026-09-27. That module held one credential per
# consumer plus a pair of outputs each, which is the shape modules/databases had
# before the 2026-09-22 slicing and wrong for the same reason: a credential
# belongs with the thing that authenticates using it.
#
# It lives in THIS module rather than ../services/zitadel because the SMTP
# config is instance-level -- see ./smtp.tf -- and so is the credential it uses.
#
# The API key still configures the `mailgun` provider in ../../providers.tf;
# that is provider configuration, not a resource, and did not move.
#
# ROTATING IT is the documented fix for the two sides diverging, and it rewrites
# both from one value:
#
#   tofu apply -replace='module.zitadel.random_password.smtp'
#
# Read the defect note in ./smtp.tf first. An UPDATE to the SMTP config does not
# reach zitadel's read model, so the password zitadel actually sends with and
# the one tofu believes it set can come apart -- which happened on 2026-09-25.
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
  region   = var.mail_region
}
