# Declares WHICH provider this module uses, not how it is configured. With no
# `configuration_aliases`, the module inherits the root's `provider "hcloud"`
# block -- so the token stays in one place.
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.69"
    }
  }
}
