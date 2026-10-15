# The photo library. One of the three copies -- the others are the originals on
# phones and the 14 TB drive at the family.
output "backup" {
  value = {
    mounts = { photos = var.library_path }
  }
}
