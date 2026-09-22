# auth.wvl.app -- zitadel and its login UI, on bumba.
#
# The last compose-managed thing on bumba, and the highest-consequence one:
# every OIDC login in the estate goes through these two containers. A CUTOVER,
# not an adoption -- a compose-created container carries com.docker.compose.*
# labels and a creation shape docker_container cannot reproduce, so an import
# would plan a recreate anyway.
#
# DELETE THE PORTAINER STACK FIRST. It is a git stack
# (/data/compose/16/home-eu-central-1/zitadel/docker-compose.yaml) which
# redeploys from this repository, so leaving it in place means portainer and
# tofu fighting over the same two containers. Then delete
# home-eu-central-1/zitadel/ from the repo so it cannot come back.
#
# NOT MANAGED HERE, and deliberately: the masterkey, zitadel_secrets.yaml,
# init-steps.yaml and the login-client directory. See var.config_path.
#
# Not to be confused with ../../zitadel, which configures what is INSIDE
# zitadel -- organisations, projects, roles, applications. This is the
# deployment; that is the contents.

resource "docker_image" "zitadel" {
  name         = "ghcr.io/zitadel/zitadel:${var.image_tag}"
  keep_locally = true
}

resource "docker_image" "login" {
  name         = "ghcr.io/zitadel/zitadel-login:${var.image_tag}"
  keep_locally = true
}

# A private bridge for the two containers.
#
# Strictly redundant: both are also on the traefik network, where the login UI
# could reach `zitadel` by the same alias. Kept because it is what compose
# built, and because it keeps login->zitadel working independently of the proxy
# network -- which is the network that gets recreated when routing changes.
#
# Renamed from compose's `zitadel_zitadel-network`: nothing outside this module
# attaches to it, so the project prefix carried no meaning.
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

  # `start-from-init` runs the bootstrap steps and then starts. The steps are
  # idempotent and have been no-ops since the instance was created in 2025.
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

  # `deploy.resources.limits.pids: 99` from the compose file is not
  # reproducible -- kreuzwerker/docker has no pids_limit. See
  # ../it-tools/main.tf for why `ulimit { name = "nproc" }` is not a substitute.

  # Published as compose had it, on all interfaces. Worth revisiting: bumba is
  # internet-facing and this is the admin API. It is reachable only if the
  # Hetzner firewall allows 3001, which it should not -- check
  # ../../hetzner/firewall.tf before assuming. Not changed here, because a
  # cutover should not also change exposure.
  ports {
    internal = 8080
    external = var.zitadel_port
  }

  upload {
    file    = "/zitadel-config.yaml"
    content = file("${path.module}/zitadel-config.yaml")
  }

  # The database credentials, generated rather than bind-mounted.
  #
  # Was /docker-volumes/zitadel/zitadel_secrets.yaml, hand-maintained, holding
  # the passwords for two roles nothing else knew about. Both roles are adopted
  # in ../../databases now and their passwords generated, so this file is
  # derived rather than kept.
  #
  # yamlencode, not a static file with placeholders: every value here is a
  # secret, and this repository is public. The key CASE matters to zitadel --
  # Database/postgres/User/Admin -- and yamlencode preserves it.
  #
  # The usernames live here rather than in zitadel-config.yaml because that is
  # where they already were; zitadel merges both --config files.
  upload {
    file = "/run/secrets/zitadel_secrets.yaml"
    content = yamlencode({
      Database = {
        postgres = {
          User = {
            Username = var.db_credentials.user_username
            Password = var.db_credentials.user_password
          }
          Admin = {
            Username = var.db_credentials.admin_username
            Password = var.db_credentials.admin_password
          }
        }
      }

      # HOW TOFU WILL AUTHENTICATE TO ZITADEL, replacing the hand-made PAT.
      #
      # A System API user is trusted because of THIS FILE, not because of a row
      # in zitadel's database -- which is the property that makes it
      # bootstrappable. A PAT has to be created through the API, so tofu could
      # never mint the credential it needs in order to call the API.
      #
      # It lives in the yamlencode'd file rather than in zitadel-config.yaml
      # deliberately. That file is static and uploaded verbatim; a stray indent
      # under SystemAPIUsers would stop zitadel booting, and zitadel fronts
      # every OIDC login here. yamlencode cannot emit invalid YAML.
      #
      # `terraform` must match the `user` in the provider's system_api block --
      # zitadel checks it against the JWT's issuer and subject claims.
      #
      # MemberType IAM scoped to this instance, NOT MemberType System. Upstream
      # (cmd/defaults.yaml) notes that System with IAM_OWNER "basically enables
      # god mode for the system user". IAM_OWNER on the instance is what the
      # PAT already had.
      SystemAPIUsers = [
        {
          terraform = {
            KeyData = base64encode(tls_private_key.system_api.public_key_pem)
            Memberships = [
              {
                MemberType  = "IAM"
                Roles       = "IAM_OWNER"
                AggregateID = var.instance_id
              },
            ]
          }
        },
      ]
    })
  }

  # The masterkey, uploaded rather than bind-mounted from the host.
  #
  # Same path and same --masterkeyFile flag as before, so zitadel sees no
  # difference. What changes is where the value LIVES: it used to exist only on
  # bumba's unbacked-up disk. See random_password.masterkey below.
  #
  # Changing this replaces the container, which is correct -- and is also why
  # the value must be exactly right. A wrong masterkey does not fail loudly; it
  # starts and cannot decrypt.
  upload {
    file    = "/run/secrets/zitadel_masterkey"
    content = random_password.masterkey.result
  }

  # Written BY zitadel at first init: login-client.pat, which zitadel-login
  # then reads. rw for that reason.
  volumes {
    host_path      = "${var.config_path}/login-client"
    container_path = "/login-client"
  }

  volumes {
    host_path      = "${var.config_path}/init-steps.yaml"
    container_path = "/zitadel-init-steps.yaml"
    read_only      = true
  }

  # traefik reaches it here, as `zitadel` -- which is why the container can be
  # renamed from compose's `zitadel-zitadel-1` without touching dynamic.yml.
  networks_advanced {
    name    = var.traefik_network
    aliases = ["zitadel"]
  }

  # postgres lives here, as `db`.
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
    # Container to container, NOT through traefik. Going via auth.wvl.app would
    # put the proxy in the path of every login's server-side calls.
    "ZITADEL_API_URL=http://zitadel:8080",
    "NEXT_PUBLIC_BASE_PATH=/ui/v2/login",
    "DEBUG=true",
    "ZITADEL_SERVICE_USER_TOKEN_FILE=/login-client/login-client.pat",

    # Zitadel decides the instance from the Host header. Without this the API
    # calls arrive with the container name and resolve to no instance.
    "CUSTOM_REQUEST_HEADERS=Host:auth.wvl.app",
  ]

  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]

  ports {
    internal = 3000
    external = var.login_port
  }

  # Read-only: zitadel writes the PAT, this only consumes it.
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

  # The PAT has to exist before this starts.
  depends_on = [docker_container.zitadel]
}

# The key pair behind the System API user above. The PUBLIC half is handed to
# zitadel in its config; the PRIVATE half stays in state and is what the
# provider signs its JWTs with.
#
# RSA because zitadel requires a public RSA key or an X.509 certificate for
# SystemAPIUsers -- ed25519 is not accepted there.
resource "tls_private_key" "system_api" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# ADOPTED, NOT GENERATED -- and it can never be regenerated. This key encrypts
# every secret in zitadel's database. A different value means zitadel starts and
# cannot read its own data; there is no migration and no reset.
#
# Imported with the existing value:
#
#   tofu import 'module.zitadel_server.random_password.masterkey' \
#     "$(bw get item 'tofu home' | jq -r '.fields[]|select(.name=="TF_VAR_zitadel_masterkey")|.value')"
#
# `ignore_changes = all` is load-bearing here beyond the usual import caveat:
# without it, ANY drift in the generation attributes plans a replacement, and a
# replacement of this resource is an unrecoverable instance.
#
# Bitwarden keeps the independent copy. That matters: state is encrypted with
# TF_VAR_state_passphrase, so if this key lived ONLY here, losing that
# passphrase would take zitadel with it.
resource "random_password" "masterkey" {
  length  = 32
  special = false

  lifecycle {
    ignore_changes = all
  }
}
