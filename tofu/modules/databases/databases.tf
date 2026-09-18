# Every database in the estate, and the roles that own them.
#
# Centralised 2026-09-18. Before that the answer to "what databases exist?"
# depended on where you looked: `zitadel` was in a module called
# modules/postgres, score's and kitchen-owl's were inside their own service
# modules, and memos was declared nowhere at all.
#
# THE TRADE, stated plainly: a service and its database are now declared in
# different files, so moving a service between hosts means remembering to change
# its provider here too. That is what was forgotten when score moved to mindy on
# 2026-09-17, leaving a complete, idle copy behind on bumba until it was dropped
# the next day. The mitigation is that both entries would now be visible side by
# side in this one file -- not that the mistake becomes impossible.
#
# Passwords are generated here and handed to services as outputs. No database
# credential is typed by a human anywhere in this repo.

# =========================================================================
# bumba -- default provider
# =========================================================================

# zitadel's own database, adopted -- see ../../imports.tf.
#
# `owner` is a plain string rather than a postgresql_role: adopting a database
# does not require its role to be a resource. zitadel_root is a SUPERUSER and
# deliberately not adopted yet; imports.tf has the two open questions.
resource "postgresql_database" "zitadel" {
  name  = "zitadel"
  owner = "zitadel_root"

  lifecycle {
    # A dropped database is not a slow apply. memos on 2026-09-15 is the worked
    # example -- deliberate that time, and the reason this layer's own state
    # lives in a database of its own.
    prevent_destroy = true
  }
}

# NOT here, on purpose:
#
#   tofu_state  holds this layer's own state. If this module managed it, the
#               credential needed to READ state would live INSIDE state.
#               Created by ../../bootstrap-state-db.sh and left alone.
#
#   postgres    the maintenance database initdb creates, and where the provider
#               connects. Nothing should manage it.
#
#   score       WAS on bumba. Dropped 2026-09-18 once the service and its data
#               had moved to mindy and the copy left behind was confirmed idle.
#               Recoverable from
#               /root/bumba-pg-dumpall-20260918-075323.sql.gz on bumba.

# =========================================================================
# mindy -- postgresql.mindy
# =========================================================================

# --- score ---------------------------------------------------------------

resource "random_password" "score_api" {
  length = 32

  # No special characters: this value goes into a libpq keyword/value DSN,
  # where an unescaped quote or backslash silently changes what connects where.
  # The same class of bug as the `p@ss` that broke PG_CONN_STR on 2026-09-16.
  special = false
}

resource "postgresql_role" "score_api" {
  provider = postgresql.mindy

  name     = "score_api"
  login    = true
  password = random_password.score_api.result
}

resource "postgresql_database" "score" {
  provider = postgresql.mindy

  name  = "score"
  owner = postgresql_role.score_api.name

  lifecycle {
    prevent_destroy = true
  }
}

# --- kitchen-owl ---------------------------------------------------------

resource "random_password" "kitchenowl" {
  length  = 32
  special = false
}

resource "postgresql_role" "kitchenowl" {
  provider = postgresql.mindy

  name     = "kitchenowl"
  login    = true
  password = random_password.kitchenowl.result
}

resource "postgresql_database" "kitchenowl" {
  provider = postgresql.mindy

  name  = "kitchenowl"
  owner = postgresql_role.kitchenowl.name

  lifecycle {
    prevent_destroy = true
  }
}

# --- memos ---------------------------------------------------------------
#
# ADOPTED, not created -- both predate tofu and are imported (../../imports.tf).
# The last database in the estate tofu did not know about.
#
# The password IS generated and rotated here rather than carried over with
# ignore_changes. Until now memos' connection string was a file bind-mounted
# from /docker-volumes/memos/db_connection_string.txt on mindy -- a credential
# that existed only on that disk, unversioned and unreproducible. Keeping the
# old password would have meant keeping that file. ../services/memo now
# generates the DSN from these values instead, which is why adopting memos
# replaces its container. The 45 notes are in postgres, not in the docker
# volume.
resource "random_password" "memos" {
  length  = 32
  special = false
}

resource "postgresql_role" "memos" {
  provider = postgresql.mindy

  name     = "memos"
  login    = true
  password = random_password.memos.result

  # NOINHERIT, as whatever created this role made it. The provider defaults to
  # inherit = true, so leaving this out silently flips it on adoption.
  #
  # Inert either way -- the role is a member of nothing, so there is nothing to
  # inherit -- but an import should change what it was asked to change and
  # nothing else. score_api and kitchenowl are inherit = true because tofu
  # created them that way, not because it was chosen.
  inherit = false
}

resource "postgresql_database" "memos" {
  provider = postgresql.mindy

  name  = "memos"
  owner = postgresql_role.memos.name

  lifecycle {
    prevent_destroy = true
  }
}

# NOT here:
#
#   immich       lives in its OWN postgres instance (immich_postgres on mindy)
#                and is created by that image at initdb from POSTGRES_DB=immich.
#                Declaring it would mean a third postgresql provider alias aimed
#                at that instance, for one database that appears anyway.
#
#   filebrowser  uses SQLite (FILEBROWSER_DATABASE=.../database.db), not
#                postgres. A `filebrowser` ROLE exists on mindy owning nothing;
#                it is a leftover and should be dropped.
