# Inherits the root's `provider "postgresql"`, which connects as the superuser
# over the tailnet. See ../../providers.tf.
terraform {
  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.25"
    }
  }
}
