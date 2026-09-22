# Declares WHICH provider this module uses, not how it is configured. With no
# `configuration_aliases`, the module inherits the root's `provider "hcloud"`
# block -- so the token stays in one place.
#
# `random` generates the two Storage Box passwords -- see storage-box.tf.
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.69"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
