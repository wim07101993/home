output "ui_password" {
  value     = random_password.ui.result
  sensitive = true
}

output "url" {
  description = "Tailnet-only. Plain HTTP over WireGuard -- see var.tailscale_ip."
  value       = "http://${var.tailscale_ip}:${var.port}/"
}
