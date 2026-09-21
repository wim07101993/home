# Storage Box credentials. Adopted into state rather than supplied each run --
# see storage-box.tf for why they are imported and never regenerated.
output "storage_box_sftp_password" {
  description = "Password for the u643732-sub1 sub-account kopia connects as."
  sensitive   = true
  value       = random_password.storage_box_sftp.result
}
