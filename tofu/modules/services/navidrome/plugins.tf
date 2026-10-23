locals {
  plugins_folder = "/plugins"

  plugins = {
    "navibeat-mixes" = {
      repo    = "nenadjokic/navibeat-mixes"
      version = "v0.9.19"
      sha256  = "e5ebb285249166810688ecea73ec2343076c2ced33e5fd41e78739445e6be9cf"
    }
  }
}

data "http" "plugin" {
  for_each = local.plugins

  url = "https://github.com/${each.value.repo}/releases/download/${each.value.version}/${each.key}.ndp"

  lifecycle {
    postcondition {
      condition     = sha256(self.response_body_base64) == each.value.sha256
      error_message = "${each.key} ${each.value.version} does not match its pinned sha256. After a version bump, update the hash -- see the top of plugins.tf."
    }
  }
}
