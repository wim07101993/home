# Zitadel's outbound mail. Verification links, password resets, OTP codes --
# without this, a new family member cannot complete a first login.
#
# ADOPTED, not created. This existed before tofu and is imported, because
# creating a second provider and marking it active would leave the original
# behind as a dormant config that still looks plausible in the console.
#
#   tofu import 'module.zitadel.zitadel_email_provider_smtp.this' \
#     '390328479847022594:placeholder'
#
# The import id is `<id>:<password>`, and the password cannot be read back out
# of zitadel -- it is encrypted with the instance masterkey. A placeholder is
# correct here rather than lazy: modules/mailgun rotates the credential on the
# same apply, so whatever is in state at import time is replaced by the real
# value immediately. Do not put the live password on that command line.
#
# `zitadel_email_provider_smtp`, not the older `zitadel_smtp_config` -- same
# schema, but the email-provider name is the one zitadel kept.
resource "zitadel_email_provider_smtp" "this" {
  description = "Mailgun EU"

  # Host carries the port. 587 is STARTTLS, which is what `tls = true` selects.
  # The alternative, implicit TLS on 465, is what postfix on samson was
  # mistakenly configured for -- it queued 23 alerts for two days rather than
  # failing loudly.
  host = "smtp.eu.mailgun.org:587"
  tls  = true

  user     = var.smtp_user
  password = var.smtp_password

  # Preserved exactly as the live config had them, so the adoption changes
  # nothing except the password. sender_name is what recipients see in the From
  # line; it currently repeats the address, which is ugly but is not something
  # to change silently as part of an import.
  sender_address   = "auth@mail.wvl.app"
  sender_name      = "auth@mail.wvl.app"
  reply_to_address = "wim@wvl.app"

  # set_active is deliberately UNSET. Omitted, the provider leaves whatever
  # state zitadel already has -- which is what an adopted, already-active
  # config needs.
  #
  # `set_active = true` is usable only at CREATION. On update the provider
  # calls Activate unconditionally, and zitadel refuses to activate a config
  # that is already active:
  #
  #   Error: failed to activate email provider smtp: FailedPrecondition
  #   Errors.SMTPConfig.AlreadyActive (COMMAND-vUHBSmBzaw)
  #
  # It fails BEFORE applying the update, so the whole change is lost -- which
  # on 2026-09-17 left zitadel holding a password that modules/mailgun had
  # already rotated, and no outbound mail, with the apply reporting only an
  # activation error.
  #
  # If this is ever recreated from scratch, activate it once in the console or
  # add set_active = true for that single apply and remove it again.
}
