terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 2.12"
    }
    # Aliased in the root at mindy:5434 -- immich's OWN cluster, not the shared
    # postgres the other services use.
    postgresql = {
      source                = "cyrilgdn/postgresql"
      version               = "~> 1.25"
      configuration_aliases = [postgresql]
    }
  }
}
