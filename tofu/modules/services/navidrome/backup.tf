output "backup" {
  value = {
    mounts = { navidrome = "/docker-volumes/navidrome" }
    paths  = ["/backup/navidrome/data"]
  }
}
