resource "docker_service" "it_tools" {
  name = "it-tools"

  task_spec {
    container_spec {
      image = "corentinth/it-tools:2024.10.22-7ca5933"
      
      healthcheck {
        test     = ["CMD", "curl", "-f", "http://localhost:80"]
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
    label = "traefik.http.routers.it-tools.rule"
    value = "Host(`it-tools.${var.domain}`)"
  }
  labels {
    label = "traefik.http.routers.it-tools.entrypoints"
    value = "websecure"
  }
  labels {
    label = "traefik.http.routers.it-tools.tls.certresolver"
    value = "le"
  }
}
