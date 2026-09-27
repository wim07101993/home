output "storage_box_sftp_password" {
  description = "Password for the u643732-sub1 sub-account kopia connects as."
  sensitive   = true
  value       = random_password.storage_box_sftp.result
}

output "storage_box_password" {
  description = "Password for the snow-white Storage Box main account (u643732)."
  sensitive   = true
  value       = random_password.storage_box.result
}

output "storage_box_id" {
  description = "ID of the snow-white Storage Box."
  value       = hcloud_storage_box.backups.id
}

# The Storage Box's FQDN, so the root can resolve it to the /32 that bumba
# advertises to the tailnet. Reachable from inside Hetzner only -- there is no
# IP allowlist on a Storage Box, so a route through a Hetzner host is the only
# way to reach it from home without making it public.
output "storage_box_host" {
  value = hcloud_storage_box.backups.server
}

# Per-host backrest sub-accounts, keyed by host. The USERNAME is computed by
# Hetzner (u643732-subN), so it cannot be written down anywhere -- the only way
# a backrest instance learns what to authenticate as is through this output.
output "backrest_sftp" {
  description = "Per-host Storage Box sub-account credentials for backrest, keyed by host."
  sensitive   = true
  value = {
    for host, sub in hcloud_storage_box_subaccount.backrest : host => {
      username = sub.username
      password = random_password.storage_box_backrest[host].result
    }
  }
}
