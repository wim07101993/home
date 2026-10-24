# What filebrowser serves and owns. audio-archive is excluded the same way it
# is excluded from the mounts, by having no source: it lives on samson, backed
# up there.
output "backup" {
  value = {
    mounts = { for s in local.shares : s.dir => s.source if s.source != null }
  }
}
