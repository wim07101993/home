# Mailgun SMTP credentials.
#
# Scope is deliberately narrow: CREDENTIALS ONLY. The sending domain itself is
# not managed here, and should not be.
#
#   - `mailgun_domain` owns dkim_selector, dkim_key_size, spam_action, click and
#     open tracking, web_scheme and force_dkim_authority. Adopting it means an
#     apply can propose changes that affect DELIVERABILITY for everything
#     sending through this domain -- including samson's OMV alerts, which are
#     the only reason the array incident was eventually reported at all.
#
#   - It could not be end-to-end anyway. A managed domain exposes the DKIM and
#     SPF records it needs via `sending_records_set`, but DNS for wvl.app lives
#     at Namecheap and is not managed by tofu. Something would still have to
#     copy them across by hand.
#
# Use the `mailgun_domain` data source if a value from the domain is ever
# needed. Do not add the resource.
#
# ONE CREDENTIAL PER SENDER. Four exist on this domain and they are deliberately
# not shared:
#
#   auth@   zitadel  -- managed here
#   gatus@  gatus    -- managed here
#   (omv)            -- samson's postfix, its own account, NOT managed here
#   (databasus)      -- its own account, to be migrated into tofu later
#
# Sharing one would mean a rotation here silently stops someone else's mail --
# queued in postfix, no error anywhere, which is precisely how the array
# incident stayed unreported for two days. It also means Mailgun's logs
# attribute every message to the service that actually sent it.
#
# When databasus moves, add it as a fourth resource here rather than reusing
# one of these.

resource "random_password" "gatus" {
  length = 32

  # Mailgun's SMTP password goes through SASL PLAIN and ends up pasted into
  # config files. Alphanumeric avoids a class of quoting bugs for no real loss
  # of entropy at this length.
  special = false
}

# A credential OF ITS OWN for gatus, not the one postfix on samson uses.
#
# This resource owns the password for whatever login it names. Pointing it at
# samson's login would mean an apply silently rotates the credential postfix
# authenticates with -- mail still generated, still queued, never delivered.
# That is exactly the failure in samson/incidents/2026-08-06-array-overheating.md,
# where 23 alerts sat in the Postfix queue for two days while every component
# reported itself healthy.
#
# Separate credentials also mean either can be rotated without the other
# noticing, and the Mailgun logs say which sender actually sent a message.
resource "mailgun_domain_credential" "gatus" {
  domain = var.domain

  # LOCAL-PART ONLY. The provider appends the domain; "gatus@mail.wvl.app" here
  # would create gatus@mail.wvl.app@mail.wvl.app.
  login    = "gatus"
  password = random_password.gatus.result
  region   = var.region
}

# zitadel's own outbound mail: verification, password reset, OTP. Distinct from
# gatus's credential so either can be rotated without taking the other's mail
# down, and so Mailgun's logs attribute a message to the right sender.
#
# ADOPTED, not created -- auth@mail.wvl.app already existed and zitadel was
# already using it. Imported rather than deleted and recreated, which would
# leave a window with no credential and would fail anyway: Mailgun rejects a
# POST for a login that exists. See README.md for the import command.
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
