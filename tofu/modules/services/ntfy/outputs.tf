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

# Donetick posts its webhook with no way to add a header, so the token rides in
# the URL: ntfy reads ?auth= as the base64url of the Authorization header.
output "donetick_webhook_url" {
  value = join("", [
    "https://${local.host}/${local.tasks_topic}?template=donetick&auth=",
    replace(replace(replace(base64encode("Bearer tk_${random_password.donetick_token.result}"), "+", "-"), "/", "_"), "/=+$/", ""),
  ])
  sensitive = true
}
