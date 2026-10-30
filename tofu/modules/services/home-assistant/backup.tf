output "backup" {
  value = {
    paths = [
      "/docker-volumes/homeassistant/config",
      "/docker-volumes/homeassistant/matterjs-server",
    ]
  }
}
