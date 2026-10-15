resource "docker_network" "this" {
  name       = var.name
  driver     = "bridge"
  attachable = false
  ingress    = false
  ipv6       = false

  dynamic "labels" {
    for_each = var.labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}
