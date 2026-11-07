resource "random_password" "rest" {
  count = var.rest_server == null ? 0 : 1

  length  = 32
  special = false
}

output "rest_server_account" {
  sensitive = true
  value = var.rest_server == null ? null : {
    username    = var.instance
    bcrypt_hash = random_password.rest[0].bcrypt_hash
  }
}

locals {
  rest_server_repositories = var.rest_server == null ? [] : [{
    plan = "${var.instance}-${var.rest_server.name}"

    repo = merge(local.repo_settings, {
      id       = var.rest_server.name
      uri      = "rest:${var.rest_server.url}/${var.instance}/"
      password = var.repository_password

      # The REST server's login, read by restic.
      env = [
        "RESTIC_REST_USERNAME=${var.instance}",
        "RESTIC_REST_PASSWORD=${random_password.rest[0].result}",
      ]
    })
  }]
}
