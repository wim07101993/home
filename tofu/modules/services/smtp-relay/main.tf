resource "docker_image" "this" {
  name         = "boky/postfix:5.1.0-alpine"
  keep_locally = true
}

resource "docker_container" "this" {
  name    = "smtp-relay"
  image   = docker_image.this.image_id
  restart = "unless-stopped"

  env = [
    "RELAYHOST=[smtp.eu.mailgun.org]:587",
    "RELAYHOST_USERNAME=${mailgun_domain_credential.smtp.login}@${var.mail_domain}",
    "RELAYHOST_PASSWORD=${random_password.smtp.result}",
    "ALLOWED_SENDER_DOMAINS=${var.mail_domain}",

    # Without it postfix offers SASL to Mailgun whether or not STARTTLS
    # succeeded, i.e. possibly in the clear.
    "POSTFIX_smtp_tls_security_level=encrypt",
  ]

  security_opts = ["no-new-privileges:true"]

  memory      = 128
  memory_swap = 256

  ports {
    internal = 587
    external = var.host_port
    ip       = "127.0.0.1"
  }
}
