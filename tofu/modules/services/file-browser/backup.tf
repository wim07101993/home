# What filebrowser serves and owns: the shares on rafiki. audio-archive lives
# on samson and is backed up there.
output "backup" {
  value = {
    mounts = { for s in local.shares : s.dir => s.source if startswith(s.source, "/mnt/rafiki/") }
  }
}
