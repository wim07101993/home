output "dashboard_password" {
  value     = random_password.dashboard.result
  sensitive = true
}
