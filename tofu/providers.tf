terraform {
  required_version = ">= 1.8.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.69"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.25"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    mailgun = {
      source  = "wgebis/mailgun"
      version = "~> 0.10"
    }
  }

  # State holds the Storage Box password in cleartext, plus every database
  # password this module grows. Three mechanisms keep that safe, and they are
  # not alternatives to each other:
  #
  #   .gitignore   keeps state out of this (public) repo
  #   pg backend   keeps it off the internet -- bumba only, over Tailscale
  #   encryption   makes it useless to whoever gets a copy anyway
  #
  # The third is what covers the copies nobody decides about: the row lands on
  # bumba's Hetzner volume, again in the pg_dump to samson, and again on the
  # 14 TB drive at the family. Every one of those is ciphertext.
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }

    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }

    state {
      method = method.aes_gcm.main
    }

    # Plan files carry the same secrets as state. `tofu plan -out=` without
    # this writes them to disk in the clear.
    plan {
      method = method.aes_gcm.main
    }
  }

  backend "pg" {
    schema_name = "tofu_infra"
  }
}

# --- providers ----------------------------------------------------------

provider "hcloud" {
}

provider "postgresql" {
  alias    = "bumba"
  host     = var.bumba_addr
  port     = 5432
  database = "postgres"
  username = "postgres"
  password = var.bumba_pg_superuser_password
  sslmode = "disable"

  max_connections = 4
}

# mindy's postgres. Aliased; bumba's is the default provider above. score's
# database and role live here after the 2026-09-17 move.
provider "postgresql" {
  alias    = "mindy"
  host     = var.mindy_addr
  port     = 5432
  database = "postgres"
  username = "postgres"
  password = var.mindy_pg_superuser_password
  sslmode  = "disable"

  max_connections = 4
}

provider "postgresql" {
  alias    = "immich"
  host     = var.mindy_addr
  port     = 5434
  database = "postgres"
  username = "postgres"
  password = var.immich_pg_superuser_password
  sslmode  = "disable"

  max_connections = 4
}

provider "docker" {
  alias = "bumba"
  host  = "ssh://root@${var.bumba_addr}"
}

provider "docker" {
  alias = "mindy"
  host  = "ssh://root@${var.mindy_addr}"
}

provider "docker" {
  alias = "samson"
  host  = "ssh://root@${var.samson_addr}"
}

provider "docker" {
  alias = "plop"
  host  = "ssh://root@${var.plop_addr}"
}

provider "zitadel" {
  domain = "auth.wvl.app"
  port   = "443"

  system_api {
    user = module.zitadel_server.system_api_user
    key  = module.zitadel_server.system_api_private_key
  }
}

provider "mailgun" {
  api_key = var.mailgun_api_key
}

# --- inputs ---------------------------------------------------------------

# Read by the `encryption` block, which OpenTofu evaluates before the resource
# graph exists -- hence an environment variable and not a tfvars file.
variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = "State encryption passphrase, 16+ chars. TF_VAR_state_passphrase."
}
