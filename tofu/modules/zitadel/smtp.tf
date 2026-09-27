# Zitadel's outbound mail. Verification links, password resets, OTP codes --
# without this, a new family member cannot complete a first login.
#
# ADOPTED, not created. It existed before tofu and was imported:
#
#   tofu import 'module.zitadel.zitadel_email_provider_smtp.this' \
#     '392334600367505411:placeholder'
#
# That id changed on 2026-09-25: the config was DESTROYED AND RECREATED to fix
# the defect below, which had left the notification sender on a stale password.
# The old 390328479847022594 no longer exists.
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

  # Normally this is UNSET: omitted, the provider leaves whatever state zitadel
  # already has, which is what an adopted and already-active config needs.
  #
  # It was set to true for the 2026-09-25 recreate and removed again straight
  # after: a newly added config is INACTIVE, but on any UPDATE the provider
  # calls Activate unconditionally and zitadel refuses:
  #
  #   Error: failed to activate email provider smtp: FailedPrecondition
  #   Errors.SMTPConfig.AlreadyActive (COMMAND-vUHBSmBzaw)
  #
  # which fails BEFORE applying the update, losing the change and reporting
  # only an activation error.

}

# --------------------------------------------------------------------------
# KNOWN DEFECT, zitadel v4.17.3 + provider 2.12.8. IT BREAKS MAIL.
#
# Called "cosmetic, not functional" here until 2026-09-25, on the strength of a
# console test mail that sent fine. That test uses a different code path from
# real notifications and proves nothing about them -- see below.
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
# THIS BREAKS MAIL. An earlier note here said the opposite -- that a test mail
# sent fine on the rotated password while the projection held the old one, so
# the sending credential must not come from the projection. That inference was
# WRONG, and it cost hours on 2026-09-25.
#
# The two paths read different sources. Measured, two minutes apart, same
# config:
#
#   TestSMTPConfigById         -> OK, mail delivered   (command/event side)
#   real passkey notification  -> CouldNotAuth 535     (projection, stale)
#
# So a passing console test proves nothing about whether users receive mail.
# The only honest check is a REAL notification -- trigger a passkey
# registration or password reset and watch for `could not connect to smtp`.
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

# --------------------------------------------------------------------------
# 2026-09-25: MAIL STOPPED SENDING. Not this defect, though it looked like it.
#
#   could not connect to smtp ... Errors.SMTP.CouldNotAuth
#     Parent=(535 "Authentication failed")
#
# The password zitadel held and the password Mailgun held had diverged. HOW is
# not established -- nothing in that session touched either side, and both are
# tofu-managed from the same random_password. Recorded as unexplained rather
# than guessed at.
#
# THE FIX, one command, because it rewrites both sides from one value:
#
#   tofu apply -replace='module.mailgun.random_password.auth'
#
# The failed projection above is a red herring here and cost an hour. It was
# still stuck at 122/123 afterwards, and mail sends fine -- which CONFIRMS the
# 2026-09-17 finding that the sending credential does not come from
# projections.smtp_configs6. A stale row there is not evidence of anything.
#
# The only reliable check remains a test send: console -> Settings ->
# Notifications -> SMTP -> Test. It logs
# `TestSMTPConfigById code=OK` and no CouldNotAuth.
#
# Ignore `could not connect using normal tls. trying starttls instead...` --
# zitadel tries implicit TLS first on every send and falls back. It is printed
# at warning level on a healthy path.
# --------------------------------------------------------------------------
