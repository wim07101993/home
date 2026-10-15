output "storage_box_password" {
  description = "Password for the snow-white Storage Box main account (u643732)."
  sensitive   = true
  value       = random_password.storage_box.result
}

output "storage_box_id" {
  description = "ID of the snow-white Storage Box."
  value       = hcloud_storage_box.backups.id
}

output "storage_box_host" {
  value = hcloud_storage_box.backups.server
}
