variable "storage_box_password" {
  type        = string
  sensitive   = true
  description = "Storage Box password. TF_VAR_storage_box_password. Reset it in the Cloud Console if it is not to hand."
}
