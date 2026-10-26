output "backup" {
  value = {
    mounts = { "adguard-home" = "/docker-volumes/adguard-home" }
    # The config only. work is blocklists, which download again, and the query
    # log, which is not worth keeping.
    paths = ["/backup/adguard-home/conf"]
  }
}
