resource "docker_image" "zitadel" {
  name         = "ghcr.io/zitadel/zitadel:v4.17.3"
  keep_locally = true
}

resource "docker_image" "login" {
  name         = "ghcr.io/zitadel/zitadel-login:v4.17.3"
  keep_locally = true
}

resource "docker_network" "internal" {
  name       = "zitadel-network"
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false
}

resource "docker_container" "zitadel" {
  name    = "zitadel"
  image   = docker_image.zitadel.image_id
  restart = "unless-stopped"

  command = [
    "start-from-init",
    "--config=/zitadel-config.yaml",
    "--config=/run/secrets/zitadel_secrets.yaml",
    "--steps=/zitadel-init-steps.yaml",
    "--masterkeyFile=/run/secrets/zitadel_masterkey",
  ]

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  ports {
    internal = 8080
    external = var.host_port
  }

  upload {
    file    = "/zitadel-config.yaml"
    content = file("${path.module}/zitadel-config.yaml")
  }

  upload {
    file = "/run/secrets/zitadel_secrets.yaml"
    content = yamlencode({
      Database = {
        postgres = {
          User = {
            Username = postgresql_role.user.name
            Password = random_password.db_user.result
          }
          Admin = {
            Username = postgresql_role.root.name
            Password = random_password.db_root.result
          }
        }
      }

      SystemAPIUsers = [
        {
          terraform = {
            KeyData = base64encode(tls_private_key.system_api.public_key_pem)
            Memberships = [
              {
                MemberType  = "IAM"
                Roles       = "IAM_OWNER"
                AggregateID = "340576542272782341"
              },
            ]
          }
        },
      ]
    })
  }

  upload {
    file    = "/run/secrets/zitadel_masterkey"
    content = random_password.masterkey.result
  }

  volumes {
    host_path      = "${var.config_path}/login-client"
    container_path = "/login-client"
  }

  volumes {
    host_path      = "${var.config_path}/init-steps.yaml"
    container_path = "/zitadel-init-steps.yaml"
    read_only      = true
  }

  networks_advanced {
    name    = var.traefik_network
    aliases = ["zitadel"]
  }

  networks_advanced {
    name    = var.db_network
    aliases = ["zitadel"]
  }

  networks_advanced {
    name    = docker_network.internal.name
    aliases = ["zitadel"]
  }
}

resource "docker_container" "login" {
  name    = "zitadel-login"
  image   = docker_image.login.image_id
  restart = "unless-stopped"

  env = [
    "ZITADEL_API_URL=http://zitadel:8080",
    "NEXT_PUBLIC_BASE_PATH=/ui/v2/login",
    "ZITADEL_SERVICE_USER_TOKEN_FILE=/login-client/login-client.pat",
    "CUSTOM_REQUEST_HEADERS=Host:auth.wvl.app",
  ]

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  ports {
    internal = 3000
    external = var.login_host_port
  }

  volumes {
    host_path      = "${var.config_path}/login-client"
    container_path = "/login-client"
    read_only      = true
  }

  networks_advanced {
    name    = var.traefik_network
    aliases = ["zitadel-login"]
  }

  networks_advanced {
    name    = docker_network.internal.name
    aliases = ["zitadel-login"]
  }

  depends_on = [docker_container.zitadel]
}

resource "tls_private_key" "system_api" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "random_password" "masterkey" {
  length  = 32
  special = false

  lifecycle {
    ignore_changes = all
  }
}
