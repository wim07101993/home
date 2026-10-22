variable "login" {
  type        = string
  description = "The Mailgun SMTP login, and so the sender: <login>@<mail_domain>. One credential per host, so revoking one host's leaves the others sending."
}

variable "mail_domain" {
  type    = string
  default = "mail.wvl.app"
}

variable "host_port" {
  type        = number
  description = "Published on 127.0.0.1 only: the relay authenticates nobody, so anything that can reach it can send as the domain. The host's own mailer is the only client."
}
