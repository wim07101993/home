terraform {
  required_providers {
    postgresql = {
      source                = "cyrilgdn/postgresql"
      version               = "~> 1.25"
      configuration_aliases = [postgresql.bumba]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
