output "backup" {
  value = {
    mounts = {
      "homeassistant"   = "/docker-volumes/homeassistant/config"
      "matterjs-server" = "/docker-volumes/homeassistant/matterjs-server"
    }
  }
}
