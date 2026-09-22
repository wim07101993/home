# A VERTICAL SLICE: this module owns everything memos needs -- its container,
# its database and role, and its zitadel project, role and OIDC client.
#
# Three providers rather than one. The docker and postgresql instances are
# passed explicitly by the root because both are per-host; zitadel is a single
# instance and inherits.
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.25"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 2.12"
    }
  }
}
