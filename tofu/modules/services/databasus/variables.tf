variable "host_port" {
  type = number
}

variable "url" {
  type        = string
  description = "Where databasus is reached. The links in its mails point here."
}

variable "mail_domain" {
  type    = string
  default = "mail.wvl.app"
}
