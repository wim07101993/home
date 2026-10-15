terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
    tls = {
      source = "hashicorp/tls"
    }
    postgresql = {
      source = "cyrilgdn/postgresql"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}
