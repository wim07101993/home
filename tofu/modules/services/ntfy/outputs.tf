output "wim_password" {
  value     = random_password.wim.result
  sensitive = true
}

output "gatus" {
  value = {
    url     = "http://ntfy:8080"
    topic   = local.topic
    network = docker_network.publishers.name
  }
}

output "gatus_token" {
  value     = "tk_${random_password.gatus_token.result}"
  sensitive = true
}
