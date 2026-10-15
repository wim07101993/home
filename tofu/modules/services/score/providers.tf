terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
    postgresql = {
      source = "cyrilgdn/postgresql"
    }
    random = {
      source = "hashicorp/random"
    }
    zitadel = {
      source = "zitadel/zitadel"
    }
  }
}
