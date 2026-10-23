output "backup" {
  value = {
    mounts = {
      databasus = "/docker-volumes/backup-server/databasus/data"

      # The dumps themselves. Under data/ they are only a symlink, which restic
      # stores as a link -- the dumps went unbacked-up until 2026-10-22.
      databasus-dumps = "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/backups/backup-server/databasus/data/backups"
    }
  }
}
