# `modules/zitadel`

Projects, roles and OIDC applications at `auth.wvl.app`.

> **Status 2026-09-17.** 21 resources created, `tofu plan` clean. Nothing is
> cut over yet: the new applications exist alongside the old ones and no
> service points at them.

## A rebuild, not an adoption

Adoption was tried and abandoned: the zitadel provider's import ids are
composite and differ per resource type, and `client_secret` cannot be read
back, so the adopted end state would have been a config full of
`ignore_changes` describing values tofu could never verify.

Rebuilding is cheap here because client ids and secrets were going to rotate
either way.

## What is NOT rebuilt, and why it matters

**Orgs and users.** In zitadel the OIDC `sub` is the user id, and users belong
to the org, not to a project. Verified 2026-09-17: memos stores that sub as the
account's *username*. Recreating users would have handed every family member a
fresh, empty memos account — and the same class of silent breakage in immich,
drive and kitchen-owl.

Leaving users alone is also why passkeys, passwords and MFA all survive.

**The `Zitadel` org** (`340576542272847877`) — the instance's own, holding the
ZITADEL project and the Management/Admin/Auth APIs and Console. That is how the
provider authenticates; managing it with the thing that depends on it is a loop
worth not building.

**The `dev` org** (`364673665767309316`) is not rebuilt because it is being
deleted — a duplicate score project pointing at localhost. Deleting an org goes
by hand, once nothing references it.

## Shape

One project per application, so access can be granted per app.

**Most of these no longer live in this module.** On 2026-09-22 each project,
role and client moved into the service that uses it — `../services/<svc>/auth.tf`
— leaving only the orgs, the SMTP provider and `home` here. The table is kept
because it describes the estate, not this directory:

| project | applications | roles |
|---|---|---|
| `Score` | score-api (api), score-web-app | score_editor, score_viewer |
| `home` | home assistant | family |
| `photos` | immich | family |
| `drive` | drive | family |
| `keuken` | transaction-importer, kitchen owl web-app | family |
| `memo` | memo | family |

| project | now lives in |
|---|---|
| `Score` | `../services/score/auth.tf` |
| `home` | here — plop has no service module |
| `photos` | `../services/immich/auth.tf` |
| `drive` | `../services/file-browser/auth.tf` |
| `keuken` | `../services/kitchen-owl/auth.tf` |
| `memo` | `../services/memo/auth.tf` |
| `status` | `../services/gatus/auth.tf` |

Every project sets `has_project_check = true`. That is what makes the split
worth having: without a grant to that project, a user cannot get a token for
its apps at all.

**Behaviour change for `keuken`:** the old `kitchen-owl` project had the check
off, so its three grants carry no roles and anyone in the org could
authenticate. It is on now, like everywhere else.

## Where the secrets come from

Nowhere in this config. `client_id` and `client_secret` are **computed** —
zitadel mints them on create and the provider reads them back.

Zitadel returns a client secret exactly once. After that it can be regenerated
but not read, so state is the only copy — which is why state is encrypted and
has a history trigger behind it.

Only four apps have a meaningful secret; the rest are public clients with
`auth_method_type = OIDC_AUTH_METHOD_TYPE_NONE`:

| has a secret | public |
|---|---|
| memo, home assistant, kitchen owl web-app, score-api | score-web-app, immich, drive, transaction-importer |

```bash
tofu output -json zitadel_apps | jq
```

## Remaining, in order

1. **Cut over the applications**, one at a time: new client id (and secret),
   restart, log in, confirm the account is recognised. Same `sub`, so memos and
   immich should see the same person.
2. **Recreate the user grants** against the new projects. Deliberately after
   the apps — a grant on a new project does nothing until something points at
   it. Roughly 25: 14 on Score, 2 people x 4 projects, 3 on keuken. The old
   ones are in `zitadel-dump/org-*/user-grants.json`.
3. **Delete the old projects** — `home (old)`, `Score (old)`, `kitchen-owl` —
   and then the `dev` org.

## Deliberate non-fixes

- `drive`'s post-logout redirect is `https://drive.wvl.app.com/login`. The typo
  is reproduced so the rebuild is like-for-like. Fix it afterwards, on purpose.
- `score-web-app` was the only app on loginV2; the provider gave no obvious way
  to set that, so it is currently V1. Set it in the console if the new login UI
  is wanted there.
