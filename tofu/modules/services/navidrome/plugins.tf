locals {
  plugins_folder = "/plugins"

  plugins = {
    "navibeat-mixes" = {
      repo    = "nenadjokic/navibeat-mixes"
      version = "v0.9.25"
      sha256  = "3549574e5b915e7321b1392c8153f9ce9b50b3005b8a32997bcf77d7b0f9c6e2"
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
