# The traefik network, extracted from ../services/reverse-proxy on 2026-09-22.
#
# IT LIVES HERE TO BREAK A CYCLE. Every service takes the network name from the
# proxy; once the proxy also takes each service's ROUTING, tofu has an edge in
# both directions and refuses to build the graph. With the network as its own
# module, both sides depend on it and neither on the other:
#
#   network  <-  services  <-  reverse-proxy
resource "docker_network" "this" {
  name       = var.name
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false

  # Whatever compose stamped on this network when it created it. Vestigial,
  # and reproduced on purpose: dropping a label FORCES REPLACEMENT, and
  # replacing the network every service on the host is attached to is not
  # something to do as a side effect of an import. prevent_destroy caught
  # exactly that on bumba, 2026-09-16.
  #
  # Per host, because they differ -- the project name and config-hash belong to
  # that host's compose stack. They were briefly hardcoded to bumba's values,
  # which would have stamped mindy's network with the wrong project.
  dynamic "labels" {
    for_each = var.labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  lifecycle {
    # WHY THIS IS STILL HERE, and what has changed.
    #
    # It said "zitadel and score are still compose-managed and attach to this by
    # name. Destroying it detaches them with no warning." That is no longer true:
    # on 2026-09-27 every container on all three shared networks reported
    # `com.docker.compose.project=<none>`, so nothing outside tofu is attached.
    # `database-db-1` merely kept its old name.
    #
    # It stays because replacing this network replaces EVERY container on the
    # host that is attached to it -- on mindy that is nine, including traefik --
    # so the guard turns "every site on this host blips" into a plan that stops
    # and asks. Remove it deliberately, for one apply, when renaming the network
    # off its compose-era name; see README.md, "Network names".
    prevent_destroy = true
  }
}
