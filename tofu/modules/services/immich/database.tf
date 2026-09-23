# immich's database role. The vertical slice, same as every other service --
# except that this one is a SUPERUSER, deliberately.
#
# Until 2026-09-23 immich connected as `postgres`, the cluster's bootstrap
# superuser. That made its password unrotatable: the postgresql provider has to
# authenticate with a stable credential, and it cannot authenticate with the
# password the same apply is changing. One role serving as both the admin
# anchor and the app credential is the whole problem.
#
# Splitting them fixes it. `postgres` stays the anchor (a variable, supplied,
# never rotated by tofu); `immich` is an ordinary generated credential:
#
#   tofu apply -replace='module.immich.random_password.db'
#
# WHY SUPERUSER, and not least privilege like memos and kitchenowl:
# immich's documented non-superuser mode requires a manual
# `ALTER EXTENSION vchord UPDATE` plus a REINDEX of face_index and clip_index
# after any vchord bump, and disables its built-in pg_dumpall backup. That
# trades a rare manual step (rotation) for a recurring one (every upgrade), on
# an estate whose two worst incidents were both silent failures of things that
# needed manual attention. The privileges here are exactly what immich already
# had, so this is not a downgrade -- it is the same access under a name tofu
# can rotate.
#
# Objects stay owned by `postgres`. A superuser bypasses ownership checks, so
# no REASSIGN OWNED across the 66 tables and 8 extensions is needed.
resource "postgresql_role" "this" {
  name      = "immich"
  login     = true
  superuser = true
  password  = random_password.db.result

  # No create_role / create_database: superuser already implies both, and a
  # flag that changes nothing is a flag someone later has to check.

  # Nothing is OWNED by this role -- the tables, database and extensions all
  # belong to `postgres`. Without this, dropping the role would issue a
  # REASSIGN OWNED that has nothing to reassign.
  skip_reassign_owned = true

  # The provider authenticates as the superuser, whose password this same apply
  # may have just rotated. The container applies that new password while
  # starting, and its healthcheck does not pass until it has -- so waiting for
  # the container is what guarantees the provider can connect at all.
  #
  # Without this the graph is free to reach here first, and the apply fails on
  # an authentication error that looks like a wrong password rather than a
  # race.
  depends_on = [docker_container.postgres]
}
