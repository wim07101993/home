# `modules/services/reverse-proxy` — bumba's traefik

Everything on bumba is reached through this: `auth.wvl.app` (zitadel and
zitadel-login), `score.wvl.app`, `score-api.wvl.app`, `partituren.wvl.app`, and
traefik's own dashboard on `wvl.app`.

mindy's traefik is **not** in scope. It stays on compose for now.

## This is a cutover, not an adoption

Everything else in this repo was adopted: `import` binds an existing object,
`tofu plan` says "No changes", nothing is touched. That does not work for a
compose-managed container.

`docker inspect traefik` shows why — the container carries
`com.docker.compose.config-hash`, `.project`, `.project.config_files`,
`.container-number`, `.replace` and more. `docker_container` cannot reproduce
that shape, so an import would plan a recreate anyway. Better to do it
deliberately.

**The network is the exception.** It is imported, not created: it already
exists, and the zitadel and score stacks stay on compose and attach to
`reverse-proxy_reverse-proxy-network` as `external: true`. Create a second one
under a different name, or destroy this one, and every service behind the proxy
detaches silently. Hence `prevent_destroy` on it and the name pinned in a
variable with a comment saying why.

## Cutover — done 2026-09-17

Kept for the record, and because mindy will need the same sequence.


Order matters. Leave the portainer stack in place and its daily git redeploy
will fight tofu for the same container name and the same ports.

```bash
# 1. the network id, for the import block in ../../../imports.tf
ssh root@<bumba> docker network ls --filter name=reverse-proxy --format '{{.ID}}  {{.Name}}'

# 2. delete the `reverse-proxy` stack in portainer.
#    Everything on bumba is down from here until step 4.
#    `docker compose down` will try to remove the network and fail, because
#    zitadel and score are still attached. That failure is expected and is
#    what keeps the network alive for the import.

# 3. confirm it is really gone, and the network really is not
ssh root@<bumba> 'docker ps -a --filter name=reverse-proxy; docker network ls'

# 4.
tofu plan      # expect: 1 to import (network), 2 to add (image, container)
tofu apply
```

Certificates survive: `acme.json` lives in the bind mount at
`/docker-volumes/traefik/letsencrypt`, not in the container. That is what makes
this cheap rather than a re-issuance storm against Let's Encrypt rate limits.

### Rollback

Recreate the stack in portainer from the repo and `tofu state rm` the
container. The compose file is unchanged in git until you delete it, which is
deliberate — do not remove `home-eu-central-1/reverse-proxy/` until this has
been running for a while.

## What changed from the compose version

- **The `baby.wvl.app` redirect is gone**, as requested. It was three labels
  and a middleware.
- **Everything else is identical**, including the traefik version. `v3.7.10` is
  pinned to what bumba runs today so the cutover changes one thing. mindy is on
  `v3.7.13`; closing that drift is a separate change.
- **Routing moved from container labels to traefik's file provider.** All six
  routes are in `routes.tf` as data. See below.
- **The docker socket is no longer mounted**, which follows from that.

## Routing is centralised

`routes.tf` holds one map. Each entry becomes a router, a service and the rule
that connects them, rendered to `/etc/traefik/dynamic.yml` by `yamlencode` and
uploaded into the container.

```hcl
zitadel = {
  rule    = "Host(`auth.wvl.app`) && !PathPrefix(`/ui/v2/login`)"
  backend = "http://zitadel:8080"
}
```

Backends use compose's per-network alias — `zitadel`, not
`zitadel-zitadel-1` — and the **container** port, not the host-published one.

Two validations, both cheap and both catching real classes of mistake: a route
must have exactly one of `backend` or `internal`, and the key must be a legal
router name. The key *is* the router and the service name, so they cannot drift
apart — which is the bug file-browser hit on 2026-09-14, where a middleware was
attached to a router that did not exist and traefik silently invented one.

### The socket is gone

With no `--providers.docker`, traefik does not need `/var/run/docker.sock`, and
it is no longer mounted. An internet-facing proxy with the docker socket is
effectively root on the host; removing it is the largest security improvement
in this change and it came for free.

### What it costs

**No auto-discovery.** A service missing from `routes.tf` is unreachable, full
stop. Adding a service now means editing this module as well as the service —
coupling in the opposite direction from labels.

**Labels elsewhere are now inert.** The `traefik.*` labels on the zitadel and
score compose files do nothing, because nothing reads them. Harmless, and worth
deleting when those stacks are next touched, so nobody edits a label expecting
an effect.

## What this costs

**dependabot goes blind.** It parses `docker-compose.yaml` and cannot see
`traefik:v3.7.10` in HCL. The moment this stack moves, its updates stop
arriving. Renovate has a `terraform` manager and should be in place before more
stacks follow — `docs/iac-migration.md`, issue 6. One stack is an acceptable
gap; seven is not.

**A container moves to tofu when its dependencies do.** traefik is the
exception rather than the rule here: it has no OIDC client, no database role
and no secrets, so it gains nothing from the dependency graph — it moves
because you want it in tofu, not because compose cannot express it.
file-browser and score are the opposite case, and they should move when their
OIDC clients and database roles do. Translating the rest of the stacks for the
sake of uniformity is the thing
[`../../../../docs/iac-migration.md`](../../../../docs/iac-migration.md)
rejects under **Rejected**, and it is still right.
