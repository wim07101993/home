terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
    random = {
      source = "hashicorp/random"
    }
    zitadel = {
      source = "zitadel/zitadel"
    }
    postgresql = {
      source = "cyrilgdn/postgresql"
    }
  }
}
