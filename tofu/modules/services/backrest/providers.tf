terraform {
  required_providers {
    docker = {
      source                = "kreuzwerker/docker"
      version               = "~> 3.0"
      configuration_aliases = [docker]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
