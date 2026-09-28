# State renames for the 2026-09-27 credential slicing. NO-OPS once applied.
#
# modules/mailgun held one SMTP credential per consumer and a pair of outputs
# for each. Each credential moved into the module that authenticates with it --
# gatus's to modules/services/gatus/mail.tf, zitadel's to
# modules/zitadel/mail.tf -- and that module is now deleted.
#
# THESE BLOCKS ARE NOT OPTIONAL. Without them tofu sees four resources disappear
# and four appear, and plans to DESTROY AND RECREATE both Mailgun credentials.
# That regenerates the passwords, and for zitadel that means an UPDATE to
# zitadel_email_provider_smtp -- which the defect documented in
# modules/zitadel/smtp.tf makes effectively unappliable, and which broke real
# mail for hours on 2026-09-25. A rename touches no API at all.
#
# After applying, `tofu plan` must report "No changes". Then delete this file --
# an applied `moved` block does nothing, and a block naming an address that no
# longer exists fails the WHOLE plan.
moved {
  from = module.mailgun.random_password.gatus
  to   = module.gatus.random_password.smtp
}

moved {
  from = module.mailgun.mailgun_domain_credential.gatus
  to   = module.gatus.mailgun_domain_credential.smtp
}

moved {
  from = module.mailgun.random_password.auth
  to   = module.zitadel.random_password.smtp
}

moved {
  from = module.mailgun.mailgun_domain_credential.auth
  to   = module.zitadel.mailgun_domain_credential.smtp
}

# --- storage box sub-accounts, same day, same reason ----------------------
#
# The backrest sub-accounts moved from a for_each in modules/hetzner into each
# backrest instance, one apiece. Renames again, and again not optional: a
# recreate would mint a NEW Hetzner-assigned username and a new password, so
# both instances would point at an empty repository under a different login.
moved {
  from = module.hetzner.hcloud_storage_box_subaccount.backrest["mindy"]
  to   = module.backrest_mindy.hcloud_storage_box_subaccount.this
}

moved {
  from = module.hetzner.random_password.storage_box_backrest["mindy"]
  to   = module.backrest_mindy.random_password.sftp
}

moved {
  from = module.hetzner.hcloud_storage_box_subaccount.backrest["samson"]
  to   = module.backrest_samson.hcloud_storage_box_subaccount.this
}

moved {
  from = module.hetzner.random_password.storage_box_backrest["samson"]
  to   = module.backrest_samson.random_password.sftp
}
