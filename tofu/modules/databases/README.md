# `modules/databases`

**Every database in the estate, and the roles that own them.** One file,
`databases.tf`, grouped by host.

Centralised 2026-09-18. Before that the answer to "what databases exist?"
depended on where you looked: `zitadel` sat in a module called
`modules/postgres`, score's and kitchen-owl's were inside their own service
modules, and `memos` was declared nowhere at all.

## Not the same thing as `services/postgres`

Different layer, different provider:

| | provider | manages |
|---|---|---|
| [`../services/postgres`](../services/postgres) | `docker` | the postgres **container**, one instance per host |
| `modules/databases` (here) | `postgresql` | the **databases and roles** inside them |

They cannot be merged: the container must exist before the provider can connect
to it. The root gives this module
`depends_on = [module.postgres_bumba, module.postgres_mindy]` for exactly that
reason — the postgresql provider dials port 5432 directly over the tailnet, so
nothing else in the graph would order it.

## Two hosts from one module

`providers.tf` declares `configuration_aliases = [postgresql.mindy]` and the
root passes both instances in. The default is bumba's; mindy's resources carry
`provider = postgresql.mindy` explicitly.

## How a service gets its credentials

```
random_password ─> postgresql_role ─> postgresql_database
                        │
                        └─> output ─> module.<service> ─> generated config
```

No database credential is typed by a human anywhere in this repo. A service
module takes `db_user`, `db_password`, `db_name` and builds its own connection
string — see [`../services/score`](../services/score) or
[`../services/memo`](../services/memo).

## The trade this makes, stated plainly

A service and its database are declared in **different files**. Moving a service
between hosts means remembering to change its provider here too.

That is what was forgotten when score moved to mindy on 2026-09-17, leaving a
complete, idle copy of its database behind on bumba until it was dropped the
next day. Centralising does not make that mistake impossible — it makes both
entries visible side by side in one file. The alternative layout (database
declared beside its service) trades that visibility for cohesion; it was built
and discarded on 2026-09-18, and the argument is in this repo's history.

## Deliberately absent

| | why |
|---|---|
| `tofu_state` | holds this layer's own state. If tofu managed it, the credential needed to **read** state would live **inside** state. Created by [`../../bootstrap-state-db.sh`](../../bootstrap-state-db.sh). |
| `postgres` | the maintenance database initdb creates, and where the provider connects. |
| `immich` | lives in its own instance (`immich_postgres` on mindy), created by that image from `POSTGRES_DB`. Managing it would need a third provider alias for one database that appears anyway. |
| filebrowser | uses SQLite, not postgres. A `filebrowser` **role** exists on mindy owning nothing — a leftover, and should be dropped. |

## Roles

An adopted role normally needs `ignore_changes = [password]`: postgres returns
only a SCRAM hash, so an imported role lands in state with `password = ""` and
the next plan proposes setting the **live** password to empty — an outage for
whatever uses it.

`memos` is the deliberate exception. Its password is generated and rotated here,
because the alternative was keeping the DSN file that lived only on mindy's
disk. See the comment on `random_password.memos`.

`zitadel_root` and `zitadel_user` are still unadopted; see
[`../../imports.tf`](../../imports.tf) for the two open questions.
