output "system_api_user" {
  description = "Name of the System API user; must match the provider's system_api.user."
  value       = "terraform"
}

output "system_api_private_key" {
  description = "PEM private key the provider signs its System API JWTs with."
  sensitive   = true
  value       = tls_private_key.system_api.private_key_pem
}
