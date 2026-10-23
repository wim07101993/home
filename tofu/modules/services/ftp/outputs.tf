output "password" {
  value     = random_password.this.result
  sensitive = true
}
