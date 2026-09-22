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

output "zitadel" {
  description = "zitadel's postgres credentials on bumba."
  sensitive   = true
  value = {
    user_username  = postgresql_role.zitadel_user.name
    user_password  = random_password.zitadel_user.result
    admin_username = postgresql_role.zitadel_root.name
    admin_password = random_password.zitadel_root.result
  }
}
