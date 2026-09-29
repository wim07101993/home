module "hetzner" {
  source = "./modules/hetzner"

}

# --- backrest: replacing kopia --------------------------------------------
#
# Ran in PARALLEL with kopia until 2026-09-29, deliberately. The repo
# formats are unrelated, so this is a fresh upload rather than a conversion, and
# a backup migration is not the place to trust a new tool before it has proven
# it can read back what it wrote.
#
# SPACE. The Storage Box is 5.5 TB with 4.6 TB available as of 2026-09-24. The
# two restic repositories duplicate roughly what kopia already holds -- samson's
# ~800 GB of selected media plus mindy's photos, audio and documents -- so the
# parallel period costs about another 0.9 TB and lands near 3.7 TB free, before
# the 14 Storage Box snapshots pin anything. Comfortable, and the number to
# watch: modules/hetzner/storage-box.tf explains why `available` falling faster
# than the daily backup size means snapshots rather than backups.
#
# kopia comes out once these two have a full retention window and one restore
# has actually been tested from the UI.
# Encrypts BOTH restic repositories. GENERATED, unlike the kopia equivalent it
# replaces.
#
# It can be generated because it configures nothing at plan time -- it is a
# string written into an uploaded config.json. That is the distinction immich's
# superuser password could not clear (see providers.tf): a provider must be
# CONFIGURED before anything is created, so a value that does not exist yet
# cannot authenticate one. Nothing here authenticates with this.
#
# ONE value for both hosts. Their repositories are separated to confine the
# Storage Box DELETE credential -- see modules/hetzner/storage-box.tf -- not to
# compartmentalise the encryption, and two irreplaceable secrets instead of one
# is a worse trade in the only scenario either matters.
#
# prevent_destroy IS NOT OPTIONAL HERE. This password has no reset path: a
# `-replace` on it, or any change to `keepers`, regenerates the value, the next
# apply writes a new config.json, and restic can no longer open either
# repository. The old value is gone from state with no copy anywhere. That is a
# different class of accident from the Storage Box passwords, which tofu also
# generates precisely because Hetzner can reset them.
#
# Read it out and keep a vault copy -- bw-seed.sh does this for you:
#
#   tofu output -raw backrest_repository_password
resource "random_password" "backrest_repository" {
  length = 32

  # No punctuation. The value is interpolated into JSON and read back by restic
  # through env; nothing here needs the extra entropy of characters that have to
  # survive three layers of quoting.
  special = false

  lifecycle {
    prevent_destroy = true
  }
}

# --- inputs ---------------------------------------------------------------


# --- mailgun --------------------------------------------------------------
#
# Replaces the hand-typed SMTP passwords: tofu CREATES those credentials, so
# this key is the only mail secret left. One key mints as many as services need.
#
# The credentials themselves are NOT here -- each lives with its consumer,
# modules/services/gatus/mail.tf and modules/zitadel/mail.tf. Only the key,
# which configures the provider, is estate-level.
#
# Scope it in the Mailgun console -- it can manage the whole account.
variable "mailgun_api_key" {
  type      = string
  sensitive = true
}

# --- outputs --------------------------------------------------------------

# Generated, and unreadable anywhere else -- the Cloud API never returns it.
#
#   tofu output -raw storage_box_password
output "storage_box_id" {
  value = module.hetzner.storage_box_id
}

output "storage_box_password" {
  value     = module.hetzner.storage_box_password
  sensitive = true
}

# The restic repository password. GENERATED, so this output is the ONLY way to
# read it -- and it must end up somewhere that is not tofu state, because state
# is encrypted with the state passphrase and these backups are what you reach
# for when something has gone badly wrong.
#
#   tofu output -raw backrest_repository_password
output "backrest_repository_password" {
  value     = random_password.backrest_repository.result
  sensitive = true
}

output "backrest_urls" {
  value = {
    mindy  = module.backrest_mindy.url
    samson = module.backrest_samson.url
  }
}
