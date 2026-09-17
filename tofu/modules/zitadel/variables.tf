# Zitadel's own outbound mail credential, minted by modules/mailgun.
#
# Passed in rather than read from the instance because the password is not
# retrievable: zitadel stores it encrypted with the masterkey and the API
# returns only the ciphertext. Whoever owns the credential has to supply it.
variable "smtp_user" {
  type = string
}

variable "smtp_password" {
  type      = string
  sensitive = true
}
