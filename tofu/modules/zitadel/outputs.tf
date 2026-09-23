# What remains here is INSTANCE-LEVEL and nothing else: the orgs and the SMTP
# provider.
#
# Every project, role and client now lives with the service that uses it
# (../services/*/auth.tf). Home assistant was the last holdout, kept here
# because plop had no service module -- it got one on 2026-09-23.
#
# The root merges the service modules' outputs so the cutover still has every
# client id in one place:
#
#   tofu output -json zitadel_apps | jq

# The orgs are instance-level, not part of any service slice, so they stay here
# and the service modules take the id as a variable.
output "org_home_id" {
  value = zitadel_org.home.id
}
