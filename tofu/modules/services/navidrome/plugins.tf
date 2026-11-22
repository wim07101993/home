locals {
  plugins_folder = "/plugins"

  plugins = {
    "navibeat-mixes" = {
      repo    = "nenadjokic/navibeat-mixes"
      version = "v0.9.33"
      sha256  = "9d1d465b5b9717f2b05286212d7e54b7c5c2569f45a8252b64879912907d54dd"
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
      error_message = "${each.key} ${each.value.version} does not match its pinned sha256. The pin hashes the base64 of the asset, not the file: curl -sL <asset url> | base64 -w0 | sha256sum."
    }
  }
}
