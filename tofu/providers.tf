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

  # postgres on bumba, reached over Tailscale. Decided 2026-09-16 --
  # docs/iac-migration.md, open question 3. README.md has the reasoning, the
  # one-time SQL and the history trigger.
  #
  # There is deliberately NO bootstrap step. This postgres already exists and
  # is not a resource in this state, so there is no chicken-and-egg and no
  # `-migrate-state` dance -- unlike an object-store backend, which tofu would
  # have had to create before it could store the state describing it.
  #
  # schema_name is `tofu_infra` for historical reasons: this module started as
  # an infra-only layer and was merged with the workload layer on 2026-09-16.
  # Renaming the schema would mean an `init -reconfigure` against a moved
  # state row, which is a real risk for zero functional gain. The name is
  # internal; this comment is the fix.
  #
  # conn_str comes from PG_CONN_STR: it carries a password and this repo is
  # public. See README.md, "Connecting".
  backend "pg" {
    schema_name = "tofu_infra"
  }
}

# --- providers ----------------------------------------------------------

provider "hcloud" {
  # Token comes from HCLOUD_TOKEN in the environment.
  #
  # Deliberately not a variable: a variable invites a terraform.tfvars beside
  # it, and this repo is public. The .gitignore covers that mistake, but not
  # making it is better than covering it.
  #
  # NOTE: merging the workload layer in cost this module the ability to run on
  # a read-only token indefinitely -- a read-only token cannot create a
  # database either. Keep using one for anything that is pure adoption or a
  # plan; the `prevent_destroy` guards are now the only thing standing between
  # a bad plan and a cpx11 that fsn1 will not re-sell.
}

# Connects as the postgres SUPERUSER, because creating roles and databases
# requires it. This is a different and more powerful credential than the one
# the backend uses: the backend connects as tofu_state, which owns nothing but
# its own database. Keeping them apart is what stops an apply that goes wrong
# from also destroying the record of what it did.
provider "postgresql" {
  host     = var.pg_host
  port     = 5432
  database = "postgres"
  username = "postgres"
  password = var.pg_superuser_password

  # No TLS certificates on this postgres; the transport is a WireGuard tunnel.
  # Which is exactly why pg_host must be a tailnet address.
  sslmode = "disable"

  # bumba is a cpx11 with 2 GB of RAM and postgres's 100-connection budget is
  # shared with every application container on the box.
  max_connections = 4
}
