terraform {
  required_providers {
    mailgun = {
      source  = "wgebis/mailgun"
      version = "~> 0.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
