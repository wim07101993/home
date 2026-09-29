# 9443 is portainer, which tofu does not manage. plex uses
# network_mode = "host", so it publishes nothing through docker -- 32400 and
# friends are taken but cannot appear here.
locals {
  samson_ports = {
    databasus = 4005
    backrest  = 9898
  }
}

check "samson_unique_ports" {
  assert {
    condition     = length(values(local.samson_ports)) == length(distinct(values(local.samson_ports)))
    error_message = "two services in samson.tf are published on the same host port"
  }
}

module "databasus" {
  source = "./modules/services/databasus"

  providers = {
    docker = docker.samson
  }

  host_port = local.samson_ports.databasus
}

module "plex" {
  source = "./modules/services/plex"

  providers = {
    docker = docker.samson
  }
}


module "backrest_samson" {
  source = "./modules/services/backrest"

  providers = {
    docker = docker.samson
  }

  instance     = "samson"
  tailscale_ip = var.samson_addr
  config_path  = "/docker-volumes/backrest"

  cpus = "4.0"


  # MOUNTED: the whole library. BACKED UP: the 48 chosen paths below.
  mounts = {
    media         = "/export/media"
    audio-archive = "/export/audio-archive"
    backups       = "/export/backups"
  }

  # The curated media list. It was shared with kopia, mount root swapped, so the
  # selection could not drift between the two systems while they ran in parallel --
  # which is exactly the drift that put the whole 8.4 TB library in scope twice
  # on 2026-09-25.
  paths = [for p in local.samson_backup_paths : "/backup/${p}"]

  repository_password = random_password.backrest_repository.result
  repo_path           = "restic"
  storage_box_id      = module.hetzner.storage_box_id
  sftp_host           = module.hetzner.storage_box_host

  # Through bumba. samson cannot authenticate to the Storage Box directly.
  connect_host = var.bumba_addr
  connect_port = module.storage_box_proxy.listen_port

  gatus_token    = module.gatus.backrest_push_token
  gatus_base_url = module.gatus.external_endpoint_base_url
  gatus_endpoint = "backups_backrest-samson"

  # THE CLIENT of the sync pair. Pushes its operations up to mindy so both
  # appear in one dashboard; samson's own UI keeps working regardless.
  #
  # Plain http over the tailnet -- the handshake is signed with the identities
  # above, so the transport is not what authenticates it.
  sync_identity = var.backrest_identity_samson
  sync_known_hosts = var.backrest_identity_mindy == null ? [] : [{
    instance_id  = "mindy"
    keyid        = var.backrest_identity_mindy.keyid
    instance_url = "http://${var.mindy_addr}:9898"
    scopes       = ["*"]
  }]

  port = local.samson_ports.backrest
}

# --- values ---------------------------------------------------------------

locals {
  # What samson backs up, RELATIVE TO THE MOUNT ROOT -- `media/live`, not
  # `/data/media/live`. backrest prepends its own root below; it is relative
  # because kopia, which mounted at /data, read the same list until 2026-09-29.
  #
  # RELATIVE because the root differed per tool: kopia mounted at /data, backrest
  # at /backup. Encoding one of them here meant the other had to rewrite the
  # prefix, and the obvious way to do that is a trap --
  #
  #   replace(line, "/data/", "/backup/")
  #
  # OpenTofu treats a SLASH-WRAPPED substring as a REGEX, so that pattern is
  # `data` and the result is `//backup//media/live`. Fifty paths that do not
  # exist, and restic would have backed up nothing while reporting success.
  # Caught in a render check on 2026-09-26.
  #
  # ONE LIST for both systems. The selection drifting between them is exactly
  # how the whole 8.4 TB library came into scope twice on 2026-09-25.
  #
  # THE 8.4 TB IS THE REASON THIS IS A LIST AT ALL. /export/media does not fit
  # in a 5.5 TB Storage Box, so the directory is mounted but never backed up
  # wholesale -- only these paths. They are a deliberate choice about what is
  # worth off-site, not a consequence of how the folders are arranged.
  #
  # Was ./modules/services/backrest/samson-media-sources.txt until 2026-09-27.
  # Inlined because a 48-line data file next to 1000 lines of config read like
  # boilerplate, and the paths are config like everything else here.
  samson_backup_paths = concat(
    ["audio-archive", "backups"],
    [
      "media/live",
      "media/movies/animated/1990-1999/The Lion King (1994)",
      "media/movies/animated/1990-1999/The Lion King II Simbas Pride (1998)",
      "media/movies/animated/2000-2009/Bob De Bouwer - Hoe Bob Een Bouwer Werd (2008)",
      "media/movies/animated/2000-2009/Bob de Bouwer - Molly geeft eerste hulp (2004)",
      "media/movies/animated/2000-2009/Bob de Bouwer - Race naar de finish (2008)",
      "media/movies/animated/2000-2009/Bob de Bouwer Werk in Uitvoering - Bob's Grote Plan (2005)",
      "media/movies/animated/2000-2009/Bob de Bouwer werk in uitvoering- Ridder Muck (2007)",
      "media/movies/animated/2000-2009/Bob de bouwer - Leve het wilde westen (2007)",
      "media/movies/animated/2000-2009/Bob de bouwer - Wendy's drukke dag (2004)",
      "media/movies/animated/2000-2009/Bob de bouwer Werk in uitvoering - Crossen met Scrambler (2006)",
      "media/movies/animated/2000-2009/Bob de bouwer en de ridders van Makelot (2004)",
      "media/movies/animated/2000-2009/Bob de bouwer werk in uitvoering - De oogst van Spud (2006)",
      "media/movies/animated/2000-2009/Bob de bouwer werk in uitvoering ‐ Packers eerste dag (2008)",
      "media/movies/animated/2000-2009/The Lion King 1½ (2004)",
      "media/series/animated/Alfred J. Kwak",
      "media/series/animated/Avatar - The Last Airbender (2005)/Season 01 - Water (2005)",
      "media/series/animated/Buurman & Buurman (1976)",
      "media/series/animated/Danny Phantom (2004)",
      "media/series/animated/David de kabouter",
      "media/series/animated/De fabeltjeskrant",
      "media/series/animated/De smufen",
      "media/series/animated/Dragonball (1986)",
      "media/series/animated/Er Was Eens ... De aarde",
      "media/series/animated/Er Was Eens ... De mens",
      "media/series/animated/Er Was Eens ... De ruimte",
      "media/series/animated/Er was eens ... Het Leven",
      "media/series/animated/Lucky Luke",
      "media/series/animated/Maya De Bij",
      "media/series/animated/Nick Bruna's Nijntje (1984)",
      "media/series/animated/Nijntje En Vriendjes (2003)",
      "media/series/animated/Noahs Island (1997)",
      "media/series/animated/Plonsters (1987)",
      "media/series/animated/Plonsters (1987)/Season 01",
      "media/series/animated/The Animals of Farthing Wood (1993)",
      "media/series/animated/Tiktak",
      "media/series/animated/Tiktak (2019-2020)",
      "media/series/live-action/'Allo 'Allo! (1982)",
      "media/series/live-action/Bumba",
      "media/series/live-action/Dag Sinterklaas",
      "media/series/live-action/Doctor Who (1963)",
      "media/series/live-action/Drake & Josh (2004)",
      "media/series/live-action/Kabouter Plop",
      "media/series/live-action/Kulderzipken",
      "media/series/live-action/Mythbusters (2003)",
      "media/series/live-action/Spring",
      "media/series/live-action/Teletubbies nl (1997)",
      "media/series/live-action/W817",
    ],
  )
}

# --- inputs ---------------------------------------------------------------

variable "samson_addr" {
  type        = string
  description = "samson's TAILNET address. Reached as root over SSH for the docker provider, like the other two hosts."
}

# samson's half of the sync pair, so its backup progress shows up in mindy's
# dashboard as well as its own. null disables sync on both sides.
#
# Generated by ./backrest-identity.sh. The reasoning for why these are supplied
# rather than generated by tofu is on backrest_identity_mindy in mindy.tf, and at
# length in that script.
variable "backrest_identity_samson" {
  type = object({
    keyid = string
    priv  = string
    pub   = string
  })
  default   = null
  sensitive = true
}

# --- outputs --------------------------------------------------------------


output "backrest_samson_password" {
  value     = module.backrest_samson.ui_password
  sensitive = true
}
