output "backup" {
  value = {
    mounts = {
      # uploaded photos of recipes and households.
      kitchen-owl = "/docker-volumes/kitchen-owl/data"
    }
  }
}
