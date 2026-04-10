resource "docker_service" "score_api" {
  name = "score-api"

  task_spec {
    container_spec {
      image = "wim07101993/score:latest"
      command = ["--config=/run/secrets/score_api_secrets"]
      
      secrets {
        secret_id   = docker_secret.score_api_secrets.id
        secret_name = docker_secret.score_api_secrets.name
        file_name   = "score_api_secrets"
      }
    }
    networks_advanced { name = var.traefik_network }
    networks_advanced { name = var.db_network }
  }

  labels {
    label = "traefik.enable"
    value = "true"
  }
  labels {
    label = "traefik.http.routers.score-api.rule"
    value = "Host(`score-api.${var.domain}`)"
  }
  labels {
    label = "traefik.http.routers.score-api.entrypoints"
    value = "websecure"
  }
  labels {
    label = "traefik.http.routers.score-api.tls.certresolver"
    value = "le"
  }
}

resource "docker_service" "score_web_app" {
  name = "score-web-app"

  task_spec {
    container_spec {
      image = "wim07101993/score-frontend:latest"
      
      healthcheck {
        test     = ["CMD", "curl", "-f", "http://localhost:80/"]
        interval = "60s"
        timeout  = "30s"
        retries  = 5
      }
    }
    networks_advanced { name = var.traefik_network }
  }

  labels {
    label = "traefik.enable"
    value = "true"
  }
  labels {
    label = "traefik.http.routers.score-web-app.rule"
    value = "Host(`score.${var.domain}`)"
  }
  labels {
    label = "traefik.http.routers.score-web-app.entrypoints"
    value = "websecure"
  }
  labels {
    label = "traefik.http.routers.score-web-app.tls.certresolver"
    value = "le"
  }
}
