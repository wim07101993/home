resource "adguard_config" "this" {
  dns = {
    upstream_dns = [
      "https://dns10.quad9.net/dns-query",
      # The router's own names: plop.home and the rest of the LAN.
      "[/home/]${var.router_addr}",
    ]
    bootstrap_dns  = ["9.9.9.10", "149.112.112.10", "2620:fe::10", "2620:fe::fe:10"]
    dnssec_enabled = true

    # Device names in the query log, from the router, instead of bare addresses.
    use_private_ptr_resolvers = true
    local_ptr_upstreams       = [var.router_addr]
  }

  lifecycle {
    replace_triggered_by = [docker_container.this]
  }
}

resource "adguard_rewrite" "this" {
  for_each = var.dns_records

  domain = each.key
  answer = each.value

  lifecycle {
    replace_triggered_by = [docker_container.this]
  }
}

resource "adguard_list_filter" "adguard_dns" {
  name = "AdGuard DNS filter"
  url  = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"

  lifecycle {
    replace_triggered_by = [docker_container.this]
  }
}
