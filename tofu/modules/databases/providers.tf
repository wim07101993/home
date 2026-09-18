# TWO postgresql providers: the default is bumba's, `mindy` is passed in by the
# root. Both are configured in ../../providers.tf and connect as the superuser
# over the tailnet.
#
# configuration_aliases is what lets a child module take a second, explicitly
# named instance of the same provider. Without it there is no way to declare
# resources on two hosts from one module.
terraform {
  required_providers {
    postgresql = {
      source                = "cyrilgdn/postgresql"
      version               = "~> 1.25"
      configuration_aliases = [postgresql.mindy]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
