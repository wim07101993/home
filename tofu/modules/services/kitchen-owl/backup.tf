output "backup" {
  value = {
    paths = [
      # uploaded photos of recipes and households.
      "/docker-volumes/kitchen-owl/data",
    ]
  }
}
