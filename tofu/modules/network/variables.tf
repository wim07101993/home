variable "name" {
  type        = string
  description = "The docker network name, as compose created it."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Compose-era labels. See the note in main.tf -- dropping one forces replacement."
}
