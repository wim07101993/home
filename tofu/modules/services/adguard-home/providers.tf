terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
    adguard = {
      source = "gmichels/adguard"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}
