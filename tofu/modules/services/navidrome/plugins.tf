locals {
  plugins_folder = "/plugins"

  plugins = {
    "navibeat-mixes" = {
      repo    = "nenadjokic/navibeat-mixes"
      version = "v0.9.28"
      sha256  = "ffe0d7bbe48e9baa03f74fb9c9312db6cf5dff3d9ccec0d684d413f3703d04fd"
      # Since 0.9.20 there is a separate build for navidrome 0.64+.
      asset = "navibeat-mixes-navidrome-0.64.ndp"
    }
  }
}

data "http" "plugin" {
  for_each = local.plugins

  url = "https://github.com/${each.value.repo}/releases/download/${each.value.version}/${each.value.asset}"

  lifecycle {
    postcondition {
      condition     = sha256(self.response_body_base64) == each.value.sha256
      error_message = "${each.key} ${each.value.version} does not match its pinned sha256. After a version bump, update the hash -- see the top of plugins.tf."
    }
  }
}
