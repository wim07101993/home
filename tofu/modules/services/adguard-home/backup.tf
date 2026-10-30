output "backup" {
  value = {
    paths = [
      # The config only. work is blocklists, which download again, and the query
      # log, which is not worth keeping.
      "/docker-volumes/adguard-home/conf"
    ]
  }
}
