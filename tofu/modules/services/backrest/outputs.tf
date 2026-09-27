# The UI password. Read it with
#
#   tofu output -raw backrest_mindy_password
#
# after the root re-exports it -- see ../../../main.tf.
output "ui_password" {
  value     = random_password.ui.result
  sensitive = true
}

output "ui_username" {
  value = var.ui_username
}

output "url" {
  description = "Tailnet-only. Plain HTTP over WireGuard -- see var.tailscale_ip."
  value       = "http://${var.tailscale_ip}:${var.port}/"
}
