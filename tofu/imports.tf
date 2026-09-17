# Adoption record and outstanding imports for this module.
#
# Merged 2026-09-16: this was two root modules (infra + workload) and is now
# ONE root module with two CHILD modules -- one state, one apply, directories
# for reading. See README.md, "Why this is one module".
#
# Import blocks live in the root and address resources inside modules by their
# full path: `module.postgres.postgresql_database.zitadel`.
#
# The rule, unchanged:
#
#   After import, `tofu plan` must report "No changes".
#
# A bad id fails the WHOLE plan, including the parts that were working -- which
# is why the second-pass blocks below stay commented until their ids are known.

# --- Hetzner: imported and applied 2026-09-16 ---------------------------
#
#   hcloud_server.bumba         100750341    cpx11, fsn1  <- NOT re-orderable
#   hcloud_server.mindy         124902827    cx43,  fsn1
#   hcloud_volume.bumba_db      103225027    100 GB, fsn1
#   hcloud_storage_box.backups  625908       bx21,  fsn1
#   hcloud_firewall.default     10051212     3 rules, both servers
#
# --- Second pass --------------------------------------------------------
#
# Commented rather than left as "TODO" because a bad id fails the WHOLE plan,
# including the parts that were working. Fill in one at a time, uncomment,
# plan, and keep the rule: the plan must report "No changes" afterwards.
#
# import {
#   to = module.hetzner.hcloud_ssh_key.wim
#   id = "TODO" # hcloud ssh-key list
# }
#
# import {
#   to = module.hetzner.hcloud_network.private
#   id = "TODO" # hcloud network list
# }
#
# DNS is the bigger one -- 13 wvl.app records still living in a web console.
# The OFFICIAL provider has carried hcloud_zone and hcloud_zone_rrset since
# v1.54 (generally available in v1.56), so no third-party provider is needed.
# See README.md, "Deliberately out of scope for now".
#
# import {
#   to = module.hetzner.hcloud_zone.wvl_app
#   id = "TODO" # hcloud zone list
# }

# --- postgres on bumba --------------------------------------------------

# --- First pass: DATABASES ONLY -----------------------------------------
#
# Deliberately no roles yet. A postgresql_role's password cannot be read back
# -- postgres stores only a SCRAM hash -- so an imported role has an empty
# `password` in state, and a plan will happily propose setting the live
# password to "". That is an outage for whatever uses it, and the second pass
# handles it properly with ignore_changes. Databases have no secret to lose,
# so they are the safe increment.
#
# `owner` is just a string here; adopting a database does not require its role
# to be a resource.

import {
  to = module.postgres.postgresql_database.zitadel
  id = "zitadel"
}

import {
  to = module.postgres.postgresql_database.score
  id = "score"
}

# --- NOT adopted, and why -----------------------------------------------
#
#   tofu_state   holds this layer's own state. Excluded permanently -- see
#                README.md. Its role is excluded for the same reason.
#
#   postgres     the default maintenance database. It is where the provider
#                connects, it is created by initdb, and nothing should manage
#                it.
#
#   memos        112 MB, and an ORPHAN. The data was migrated to mindy on
#                2026-09-15; this is what was left behind. Drop it once the
#                notes are confirmed visible in the UI. Adopting it would mean
#                importing a mistake and then having to remove it from state
#                again.
#
# --- docker on bumba ----------------------------------------------------
#
# The traefik CONTAINER is not imported. A compose-created container carries
# com.docker.compose.* labels and a creation shape docker_container cannot
# reproduce, so an import would plan a recreate regardless. It is a cutover:
# delete the portainer stack, then apply. See
# modules/services/reverse-proxy/README.md.
#
# The NETWORK is different and must be imported rather than created. It already
# exists, and the zitadel and score stacks -- still on compose -- attach to it
# by name as `external: true`. Letting tofu create a second one, or destroying
# this one, silently detaches every service behind the proxy.
#
# Docker permits two networks with the SAME NAME -- names are not unique, ids
# are. So a missing import here does not fail loudly: it creates a second
# `reverse-proxy_reverse-proxy-network`, and the compose stacks resolving by
# name get an ambiguity error instead.
# Imported and applied 2026-09-17, alongside the container cutover. Spent; the
# block stays only until the next tidy-up, like the Hetzner ones above.
import {
  to = module.reverse_proxy_bumba.docker_network.this
  id = "8cbcf563cec4" # `docker network ls` on bumba. The ID, not the name.
}

# --- docker on mindy ----------------------------------------------------
#
# Same shape as bumba: the container is a cutover, the network is an import.
# Every mindy stack attaches to `traefik_traefik-network` as `external: true`,
# and docker permits two networks with the same NAME -- so a missing import
# creates a duplicate rather than failing, and the compose stacks then hit an
# ambiguity error.
#
import {
  to = module.reverse_proxy_mindy.docker_network.this
  id = "573ae05293d15b6970c61327afaaf8a25682dc072a8b7b1809d763bc3af66886"
}

# --- zitadel ------------------------------------------------------------
#
# Nothing to import. Zitadel is a REBUILD, not an adoption: projects, roles,
# applications and user grants are declared fresh and the old projects deleted
# afterwards. Orgs and USERS are left alone, which is what keeps every OIDC
# `sub` stable -- see modules/zitadel/orgs.tf.
#
# Adoption was tried first and abandoned for good reasons: composite import ids
# that differ per resource type, and a client_secret that cannot be read back,
# so the adopted end state would have been a config full of ignore_changes
# describing values tofu could never verify.

# --- Second pass: ROLES -------------------------------------------------
#
# Blocked on two questions, not on effort.
#
# 1. The three `databasus-*` roles. They are login roles owning no database,
#    auto-named with a hex suffix, and `databasus-41ec78f0` is the one the
#    memos dump referenced. If databasus PROVISIONS these, then tofu adopting
#    them means two systems managing the same objects -- the portainer problem
#    in a different costume. Find out what creates them first.
#
# 2. `zitadel_root` is a SUPERUSER (rolsuper = t). Zitadel needs elevated
#    rights to create its schema at first boot; it does not need superuser
#    forever. Worth checking against Zitadel's own requirements before
#    encoding the current state as intentional.
#
# When they are adopted, every one needs this, without exception:
#
#   lifecycle {
#     ignore_changes = [password]   # postgres returns only a SCRAM hash
#   }
#
# import { to = module.postgres.postgresql_role.zitadel_root, id = "zitadel_root" }
# import { to = module.postgres.postgresql_role.zitadel_user, id = "zitadel_user" }
# import { to = module.postgres.postgresql_role.score_api,    id = "score_api"    }
#
#   memos  -- drop alongside the memos database, not adopt
