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
