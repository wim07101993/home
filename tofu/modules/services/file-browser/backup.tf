output "backup" {
  value = {
    paths = concat(
      # data directories, but only thw ones on rafiki, not the ones on samson
      [for s in local.shares : s.source if startswith(s.source, "/mnt/rafiki/")],
      # config directory
      ["/docker-volumes/filebrowser/config"],
    )
  }
}
