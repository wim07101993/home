# What filebrowser serves and owns. audio-archive is excluded by the same `bind`
# flag that excludes it from the mounts: it lives on samson, backed up there.
output "backup" {
  value = {
    mounts = { for s in local.shares : s.dir => "/docker-volumes/filebrowser/files/${s.dir}" if s.bind }
  }
}
