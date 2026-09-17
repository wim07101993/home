# Zitadel's outbound mail. Verification links, password resets, OTP codes --
# without this, a new family member cannot complete a first login.
#
# ADOPTED, not created. It existed before tofu and was imported:
#
#   tofu import 'module.zitadel.zitadel_email_provider_smtp.this' \
#     '390328479847022594:placeholder'
#
# The import id is `<id>:<password>`, and the password cannot be read back out
# of zitadel -- it is encrypted with the instance masterkey. A placeholder was
# correct there rather than lazy: modules/mailgun rotated the credential on the
# same apply, so the seeded value was replaced immediately. Do not put a live
# password on that command line.
#
# `zitadel_email_provider_smtp`, not the older `zitadel_smtp_config` -- same
# schema, but the email-provider name is the one zitadel kept.
resource "zitadel_email_provider_smtp" "this" {
  # "mailgun", lowercase, because that is what the API reports -- NOT a nicer
  # label. See the defect note below: a changed description is written to the
  # eventstore, rejected by the projection, and never read back, so the plan
  # would propose the same update on every run, forever. Every attribute here
  # must match what zitadel currently returns.
  description = "mailgun"

  # Host carries the port. 587 is STARTTLS, which is what `tls = true` selects.
  # The alternative, implicit TLS on 465, is what postfix on samson was
  # mistakenly configured for -- it queued 23 alerts for two days rather than
  # failing loudly.
  host = "smtp.eu.mailgun.org:587"
  tls  = true

  user     = var.smtp_user
  password = var.smtp_password

  sender_address   = "auth@mail.wvl.app"
  sender_name      = "auth@mail.wvl.app"
  reply_to_address = "wim@wvl.app"

  # set_active is deliberately UNSET. Omitted, the provider leaves whatever
  # state zitadel already has -- which is what an adopted, already-active
  # config needs.
  #
  # `set_active = true` is usable only at CREATION. On update the provider calls
  # Activate unconditionally and zitadel refuses to activate an already-active
  # config:
  #
  #   Error: failed to activate email provider smtp: FailedPrecondition
  #   Errors.SMTPConfig.AlreadyActive (COMMAND-vUHBSmBzaw)
  #
  # It fails BEFORE applying the update, so the whole change is lost while the
  # apply reports only an activation error. Hit on 2026-09-17.
  #
  # If this is ever recreated from scratch, activate it once in the console, or
  # add set_active = true for that single apply and remove it again.
}

# --------------------------------------------------------------------------
# KNOWN DEFECT, zitadel v4.17.3 + provider 2.12.8 -- cosmetic, not functional.
#
# An update writes an `instance.smtp.config.changed` event carrying the password
# TWICE, at the top level and again under `plainAuth`:
#
#   {"id": "...", "password": {...}, "plainAuth": {"password": {...}}, ...}
#
# Zitadel's own projection then builds an UPDATE assigning the same column
# twice, and postgres rejects it:
#
#   projections.smtp_configs6   failed_sequence 122/123   failure_count 5
#   ERROR: multiple assignments to same column "password" (SQLSTATE 42601)
#
# It retries 5 times, gives up, and skips the event, so the row in
# projections.smtp_configs6_smtp keeps the OLD ciphertext and description.
#
# VERIFIED 2026-09-17 that mail still SENDS correctly after such an update --
# a test mail went out on the rotated password while the projection still held
# the old one. So zitadel does not source the sending credential from that
# projection. Do not conclude from a stale `smtp_configs6_smtp` row that mail is
# broken; send a test mail, which is the only reliable check.
#
# THE PRACTICAL CONSEQUENCE IS NOT COSMETIC: this resource is effectively
# READ-ONLY to tofu. Because the write never reaches the read model, the API
# keeps returning the old value, so tofu sees the same drift on the next plan
# and proposes the same update again -- an apply that reports success, changes
# nothing, and never converges.
#
# Hit immediately: changing `description` to "Mailgun EU" produced a permanent
# 1-to-change plan. Every attribute below therefore mirrors what zitadel
# currently returns. Do not "improve" any of them -- including sender_name,
# which repeats the address and looks wrong -- until the upstream bug is fixed.
# Changing them means editing in the CONSOLE first, then matching here.
#
# `instance.smtp.config.added` carries only `plainAuth` and projects cleanly,
# so creates are unaffected. Worth fixing upstream: the changed-event reducer
# should set `password` once.
# --------------------------------------------------------------------------
