terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
    random = {
      source = "hashicorp/random"
    }
    postgresql = {
      source = "cyrilgdn/postgresql"
    }
    zitadel = {
      source = "zitadel/zitadel"
    }
  }
}
