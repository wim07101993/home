# Consumed by the service modules, which build their own connection strings.
#
# Grouped per service rather than exposed as one map, so a service module takes
# exactly the three values it needs and nothing else.

output "score" {
  description = "score-api's database credentials on mindy."
  sensitive   = true
  value = {
    user     = postgresql_role.score_api.name
    password = random_password.score_api.result
    name     = postgresql_database.score.name
  }
}

output "kitchenowl" {
  description = "kitchen-owl's database credentials on mindy."
  sensitive   = true
  value = {
    user     = postgresql_role.kitchenowl.name
    password = random_password.kitchenowl.result
    name     = postgresql_database.kitchenowl.name
  }
}

output "memos" {
  description = "memos' database credentials on mindy."
  sensitive   = true
  value = {
    user     = postgresql_role.memos.name
    password = random_password.memos.result
    name     = postgresql_database.memos.name
  }
}
