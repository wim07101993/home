output "backup" {
  value = {
    mounts = merge(
      # data directories, but only thw ones on rafiki, not the ones on samson
      { for s in local.shares : s.dir => s.source if startswith(s.source, "/mnt/rafiki/") },
      # config directory
      { filebrowser = "/docker-volumes/filebrowser/config" },
    )
  }
}
