output "backup" {
  value = {
    paths = [
      # Decrypts the credentials, and is all a manual recovery of the dumps
      # needs. Not pgdata, its own configuration: a running postgres cannot be
      # copied file by file, and databasus never shuts it down cleanly.
      "/docker-volumes/backup-server/databasus/data/secret.key",

      # The dumps themselves. Under data/ they are only a symlink, which restic
      # stores as a link
      "/srv/dev-disk-by-uuid-25d0f3ec-68a9-4ce0-891e-0966088e5300/backups/backup-server/databasus/data/backups",
    ]
  }
}
