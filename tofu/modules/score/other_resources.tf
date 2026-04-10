resource "docker_secret" "score_api_secrets" {
  name = "score_api_secrets_v1"
  data = base64encode(file("${path.module}/../../../home-eu-central-1/score/score_api_secrets.json"))
}

