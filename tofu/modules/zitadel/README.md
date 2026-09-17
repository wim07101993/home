# `modules/zitadel`

Orgs, projects and OIDC applications at `auth.wvl.app`.

This is the part of the workload layer that compose cannot express at all:
thirteen `wvl.app` hostnames whose OIDC clients were clicked into a console by
hand, with the client id then pasted into a config file.

## Adoption only, for now

Same rule as everywhere else: import what exists, plan to **No changes**, then
change things deliberately. Nothing here creates an org or an application yet.

## What is deliberately excluded

| | |
|---|---|
| org `Zitadel` (`340576542272847877`) | the instance's own org |
| project `ZITADEL` (`340576542272913413`) | and its Management-API, Admin-API, Auth-API and Console apps |

Zitadel creates and maintains those itself. They are how the provider
authenticates; managing them with the thing that depends on them is a loop
worth not building.

## Inventory, 2026-09-17

| org | project | applications |
|---|---|---|
| `Home` `342055441280270340` | `Score` `342055456111329284` | score-api (api), score-web-app (oidc) |
| | `home` `345239897906348035` | home assistant, immich, drive, memo |
| | `kitchen-owl` `376238041037012995` | transaction-importer (native), kitchen owl web-app |
| `dev` `364673665767309316` | `score` `364673680380264452` | score web, score api (api), score-native (native) |

Eleven applications across four projects.

## Staged, deliberately

1. **orgs** — two resources, proves the provider wiring and the import id format
2. **projects** — four
3. **applications** — eleven, and the ones that matter

The zitadel provider's import ids are composite and the exact shape differs per
resource type. Rather than guess, stage 1 exists to find out: import one, read
the error if it is wrong, and apply the same shape to the rest.

Note that an OIDC application's `client_secret` cannot be read back, the same
problem as `hcloud_storage_box.password` and every `postgresql_role`. Expect
`ignore_changes = [client_secret]` on anything that has one, or an import id
that includes it.
