terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.1.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.26.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 2.12.0"
    }
  }
}
