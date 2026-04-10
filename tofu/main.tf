terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.1.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.26.0"
    }
    # For Zitadel management if needed, though we might use docker provider for the service itself
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

# The postgres provider will be configured after the DB is up, or we can use a dynamic configuration
# For the sake of this setup, we'll assume the DB is reachable.
provider "postgresql" {
  host            = "db" # Should be reachable via docker network
  port            = 5432
  username        = "postgres"
  password        = var.db_password
  sslmode         = "disable"
  connect_timeout = 15
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "domain" {
  type    = string
  default = "wvl.app"
}

# Shared Networks
resource "docker_network" "traefik_network" {
  name   = "traefik-network"
  driver = "overlay"
  attachable = true
}

resource "docker_network" "db_network" {
  name   = "db-network"
  driver = "overlay"
  attachable = true
}

module "database" {
  source      = "./modules/database"
  db_password = var.db_password
  db_network_id  = docker_network.db_network.id
}

module "traefik" {
  source     = "./modules/traefik"
  network_id = docker_network.traefik_network.id
  domain     = var.domain
}

module "zitadel" {
  source          = "./modules/zitadel"
  traefik_network = docker_network.traefik_network.name
  db_network      = docker_network.db_network.name
  domain          = var.domain
}

module "memo" {
  source          = "./modules/memo"
  traefik_network = docker_network.traefik_network.name
  db_network      = docker_network.db_network.name
  domain          = var.domain
}

module "file_browser" {
  source          = "./modules/file-browser"
  traefik_network = docker_network.traefik_network.name
  db_network      = docker_network.db_network.name
  domain          = var.domain
}

module "homepage" {
  source          = "./modules/homepage"
  traefik_network = docker_network.traefik_network.name
  domain          = var.domain
}

module "it_tools" {
  source          = "./modules/it-tools"
  traefik_network = docker_network.traefik_network.name
  domain          = var.domain
}

module "score" {
  source          = "./modules/score"
  traefik_network = docker_network.traefik_network.name
  db_network      = docker_network.db_network.name
  domain          = var.domain
}

module "immich" {
  source          = "./modules/immich"
  traefik_network = docker_network.traefik_network.name
  domain          = var.domain
  db_password     = var.db_password
}
