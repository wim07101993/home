output "backup" {
  value = {
    paths = [
      # entire photo library
      var.library_path
    ]
  }
}
