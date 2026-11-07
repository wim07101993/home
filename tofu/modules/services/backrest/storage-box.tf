resource "hcloud_storage_box_subaccount" "this" {
  storage_box_id = var.storage_box.id

  name           = "backrest-${var.instance}"
  home_directory = "backrest/${var.instance}/"
  description    = "restic repository for the backrest instance on ${var.instance}."

  password = random_password.sftp.result

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

resource "random_password" "sftp" {
  length           = 32
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@#%^*()-_=+"
}

locals {
  storage_box_port = 23

  storage_box_connect = coalesce(var.storage_box.via, {
    host = var.storage_box.host
    port = local.storage_box_port
  })

  storage_box_repository = {
    plan = var.instance

    repo = merge(local.repo_settings, {
      id = "storagebox"

      uri      = "rclone:storagebox:restic"
      password = var.repository_password
    })
  }

  storage_box_env = [
    "RCLONE_CONFIG_STORAGEBOX_TYPE=sftp",
    "RCLONE_CONFIG_STORAGEBOX_HOST=${local.storage_box_connect.host}",
    "RCLONE_CONFIG_STORAGEBOX_PORT=${local.storage_box_connect.port}",
    "RCLONE_CONFIG_STORAGEBOX_USER=${hcloud_storage_box_subaccount.this.username}",

    # Hetzner's SFTP does not implement the extensions rclone uses to check free
    # space, and without this every operation logs a warning about it.
    "RCLONE_CONFIG_STORAGEBOX_DISABLE_HASHCHECK=true",

    # HOST KEY VALIDATION. Off by default in rclone, which says so on every
    # operation:
    #
    #   NOTICE: No host key validation is being performed. Set known_hosts_file
    #
    # kopia pinned these and dropping the property silently would be the wrong
    # way to migrate. restic encrypts client-side, so the risk is not disclosure
    # -- it is talking to something that is not the Storage Box and believing the
    # repository it serves.
    "RCLONE_CONFIG_STORAGEBOX_KNOWN_HOSTS_FILE=/app/known_hosts",
  ]

  # The Storage Box's SSH HOST public keys. Not a secret, and committed as
  # ./known_hosts so a changed host key shows up as a diff rather than as a
  # connection that silently starts trusting something else.
  #
  # REWRITTEN, not read verbatim. known_hosts entries are keyed by the address
  # you dial -- `[u643732.your-storagebox.de]:23` -- so samson, which goes
  # through bumba's forwarder, is offered the Storage Box's own host key from a
  # different address and validation fails. Only the pattern changes; the key
  # material is untouched, so a forwarder pointing somewhere else is still
  # caught.
  #
  # Its own copy rather than ../kopia/known_hosts: that module is being deleted.
  storage_box_known_hosts = replace(
    file("${path.module}/known_hosts"),
    "[${var.storage_box.host}]:${local.storage_box_port}",
    "[${local.storage_box_connect.host}]:${local.storage_box_connect.port}",
  )
}
