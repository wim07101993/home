# `snow-white`, bx21, fsn1. kopia's off-site repository -- one of the three
# copies of the family photos.
#
# This is the resource that could not be generated: the Cloud API never returns
# the password, so `-generate-config-out` wrote `password = null` and the plan
# refused. It has to be supplied.

resource "hcloud_storage_box" "backups" {
  name             = "snow-white"
  storage_box_type = "bx21"
  location         = "fsn1"
  password         = random_password.storage_box.result

  # Hetzner-side protection: blocks deletion from the API and the Cloud Console,
  # not just from tofu. `prevent_destroy` below only stops tofu.
  #
  # Was false because import captured whatever the console had -- the volume
  # happened to have it on and this did not. The asymmetry ran the wrong way:
  # a storage box holding every backup was less protected than a 100 GB volume.
  #
  # Cost: a real teardown becomes two applies -- flip this, then destroy.
  delete_protection = true
  ssh_keys          = []

  # THE ONLY THING AN SFTP CLIENT CANNOT DELETE.
  #
  # delete_protection above guards the Hetzner API. It does nothing about the
  # SFTP credential, which can `rm -rf` the repository -- and from 2026-09-24
  # that credential lives on samson and plop as well as mindy, because all
  # three share one repository. kopia encrypts client-side, so the risk here
  # was never disclosure; it is destruction, accidental or otherwise.
  #
  # Hetzner takes these at the box level, outside any SFTP session's reach.
  # 14 daily copies is sized against how long a deletion could go unnoticed:
  # kopia's heartbeat turns stale within 26h and gatus mails after three
  # failed sweeps, so ~2 days to notice and twelve to act.
  #
  # 07:00 UTC, after the 05:00 kopia run and the 00:00-01:00 database dumps, so
  # each snapshot contains that day's backups rather than catching them
  # half-written.
  #
  # WILL 14 FIT? These are filesystem-level, so 14 is not 14 copies -- each
  # costs only the blocks changed or deleted since it was taken. Baseline
  # measured 2026-09-24, immediately before the first one:
  #
  #   capacity 5.5 TB   available 4.6 TB
  #
  # Daily churn is dominated by the database dumps, ~255 MB/day and poorly
  # deduplicated because compressed dumps differ. Call it single-digit GB
  # across the window.
  #
  # The subtle cost is kopia's own deletions: when GFS retention expires a
  # snapshot, maintenance frees the blobs, but a Storage Box snapshot PINS
  # them for up to 14 more days. That matters exactly once -- when retention
  # finally drops mindy's ~800 GB of media sources after samson takes them
  # over. Still comfortable at 4.6 TB free, but it is the case to watch.
  #
  # If `available` ever falls faster than the daily backup size, snapshots are
  # why and max_snapshots is the dial. A full box means kopia cannot write, so
  # this is monitored rather than assumed -- the heartbeat goes stale in 26h.
  snapshot_plan = {
    max_snapshots = 14
    hour          = 7
    minute        = 0

    # null = every day. Both must be null for daily; setting either narrows it
    # to that weekday or day-of-month.
    day_of_week  = null
    day_of_month = null
  }

  access_settings = {
    reachable_externally = false
    samba_enabled        = false
    ssh_enabled          = true
    webdav_enabled       = false
    zfs_enabled          = false
  }

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      # ssh_keys is the dangerous one, and not theoretically: provider v1.58.0
      # changed it from ignored to replacement-forcing. The Hetzner API has no
      # update path for those keys, so the provider's only way to reconcile a
      # difference is destroy-and-recreate -- which would take the off-site
      # kopia repository with it.
      ssh_keys,

      # `password` was here too, because the API never returns it and tofu could
      # not tell a stale config value from the live one. That ended when tofu
      # became the only writer -- see random_password.storage_box below.
    ]
  }
}

# GENERATED, and tofu is the only writer.
#
# It was adopted with ignore_changes = all while the real value lived in
# Bitwarden. That is no longer needed: `password` carries no RequiresReplace
# (unlike `ssh_keys` on the same resource) and Update calls the Storage Box
# ResetPassword action, so a change is an in-place rotation and not a rebuild of
# the box holding every backup.
#
# NOT the credential kopia uses. That is the sub-account below. This is the MAIN
# account: Cloud Console login, SMB, and SSH as u643732.
#
# The API never returns it, so the output is the only way to read it back:
#
#   tofu output -raw storage_box_password
#
# The min_ values are REQUIRED, not defensive. Hetzner enforces a password
# policy and rejects the whole apply otherwise:
#
#   invalid input in field password (invalid_input) 422
#   The password must contain at least one upper case letter, one lower case
#   letter, one number, and a special character
#
# random_password only guarantees a class is PRESENT if a min_ is set for it --
# by default it merely permits them, so a generated value can legitimately
# contain none and fail this intermittently, at apply time.
resource "random_password" "storage_box" {
  length           = 32
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@#%^*()-_=+"
}

# The sub-account kopia connects as. ADOPTED (created by hand in the Cloud
# Console), with its password now generated.
#
# kopia reaches it as sftp://u643732-sub1@... with path "backup", which is
# RELATIVE TO home_directory -- so the repository lives at backup/backup on the
# box. home_directory is Required but NOT replace-forcing: a wrong value moves
# the directory rather than destroying the sub-account, which is visible in the
# plan and recoverable, but it would take kopia's repository with it.
#
# Imported as "<storage_box_id>/<subaccount_id>", e.g. 625908/281501.
resource "hcloud_storage_box_subaccount" "kopia" {
  storage_box_id = hcloud_storage_box.backups.id

  # A LABEL, not the login. `username` is computed and assigned by Hetzner
  # (u643732-sub1); kopia authenticates with that and is unaffected by this.
  # It defaulted to the username, which made the two look like one field.
  #
  # Pinned rather than omitted: `name` is Optional+Computed, so leaving it out
  # shows "known after apply" on every plan.
  name           = "kopia"
  home_directory = "backup/"
  description    = "Repository target for the kopia server on mindy."

  password = random_password.storage_box_sftp.result

  access_settings = {
    reachable_externally = false
    samba_enabled        = false
    ssh_enabled          = true
    webdav_enabled       = false
    readonly             = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

# GENERATED. Same policy minimums as the main account -- see above.
#
# Rotating this recreates the kopia container, because its repository.config is
# generated from this value. Both happen in one apply.
resource "random_password" "storage_box_sftp" {
  length           = 32
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@#%^*()-_=+"
}

# --- backrest ---------------------------------------------------------------
#
# ONE SUB-ACCOUNT PER HOST, which is the point. kopia above shares a single
# credential across mindy, samson and plop, and that credential can `rm -rf`
# the entire backup/ tree -- the risk this file already names as "destruction,
# accidental or otherwise". A sub-account is confined to its home_directory, so
# samson holding its own credential can no longer reach mindy's repository, and
# neither can reach kopia's.
#
# That confinement is the reason restic gets separate repositories per host
# rather than the one shared repository kopia uses. Cross-host deduplication is
# the thing given up, and it is worth nothing here: mindy backs up photos,
# audio and documents, samson backs up the array. They share no bytes.
#
# home_directory is Required and NOT replace-forcing -- a wrong value moves the
# directory rather than destroying the sub-account. Visible in the plan,
# recoverable, but it would take the repository with it.
resource "hcloud_storage_box_subaccount" "backrest" {
  for_each = toset(["mindy", "samson"])

  storage_box_id = hcloud_storage_box.backups.id

  # A LABEL, not the login. `username` is computed and assigned by Hetzner
  # (u643732-subN) -- see the note on the kopia sub-account above.
  name           = "backrest-${each.key}"
  home_directory = "backrest/${each.key}/"
  description    = "restic repository for the backrest instance on ${each.key}."

  password = random_password.storage_box_backrest[each.key].result

  access_settings = {
    reachable_externally = false
    samba_enabled        = false
    ssh_enabled          = true
    webdav_enabled       = false
    readonly             = false
  }

  # ON FROM THE START, deliberately, even though these repositories are empty
  # on the day they are created. The cost is that a rollback takes two applies;
  # the benefit is that the accident worth preventing -- deleting the
  # sub-account that holds a host's only off-site copy -- cannot happen in one.
  #
  # Turning it on "later, once there is data" is the version of this that gets
  # forgotten.
  lifecycle {
    prevent_destroy = true
  }
}

# GENERATED. Same Hetzner password policy as the accounts above -- the min_
# values are required, not defensive; see random_password.storage_box.
#
# Rotating one of these recreates that host's backrest container, because the
# rclone credential is read from a file the container spec uploads. Both happen
# in one apply.
resource "random_password" "storage_box_backrest" {
  for_each = toset(["mindy", "samson"])

  length           = 32
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@#%^*()-_=+"
}
