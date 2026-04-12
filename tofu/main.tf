provider "docker" {
  host = "unix:///var/run/docker.sock"
}

provider "random" {}

# The postgres provider will be configured after the DB is up, or we can use a dynamic configuration
# For the sake of this setup, we'll assume the DB is reachable.
provider "postgresql" {
  host            = "db" # Should be reachable via docker network
  port            = 5432
  username        = "postgres"
  password        = random_password.db_password.result
  sslmode         = "disable"
  connect_timeout = 15
}

provider "zitadel" {
  domain = "auth.${var.domain}"
  insecure = false
  # Port is 443 by default for https
  # jwt_profile_json is usually used for machine user auth
  # For the initial setup, we might need a different approach if we don't have a key yet.
  # But the requirement is to use the provider.
}

module "database" {
  source      = "./modules/database"
  db_password = random_password.db_password.result
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
  user_password   = random_password.zitadel_user_password.result
  root_password   = random_password.zitadel_root_password.result
  masterkey       = random_password.zitadel_masterkey.result
}

module "memo" {
  source          = "./modules/memo"
  traefik_network = docker_network.traefik_network.name
  db_network      = docker_network.db_network.name
  domain          = var.domain
  db_password     = random_password.memo_db_password.result
}

module "file_browser" {
  source             = "./modules/file-browser"
  traefik_network    = docker_network.traefik_network.name
  db_network         = docker_network.db_network.name
  db_password        = random_password.file_browser_db_password.result
  domain             = var.domain
  zitadel_org_id     = module.zitadel.zitadel_org_id
  zitadel_project_id = module.zitadel.zitadel_project_id
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
  db_password     = random_password.db_password.result
}
