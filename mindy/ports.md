# USED ports

Host ports published by the compose stacks and tofu modules in this directory.
Derived from the `ports:` lines, 2026-09-17.

| Port  | Service              |
|-------|----------------------|
| 80    | traefik http         |
| 443   | traefik https        |
| 3000  | it-tools             |
| 3001  | homepage             |
| 3002  | kitchen-owl          |
| 3007  | memo                 |
| 3008  | uptime-kuma *        |
| 5432  | postgres             |
| 5433  | kitchen-owl postgres |
| 5434  | immich postgres      |
| 8900  | file-browser         |
| 51515 | kopia                |

\* `mindy/uptime-kuma/` declares this, but the container has never existed --
`docker network inspect` on 2026-09-17 listed seven containers and it was not
among them. It is going to bumba instead, so that stack should be deleted.

**immich does not publish a host port.** The old version of this file listed
2283; immich-server is reached only through traefik on the docker network. It
also listed 8000 for paperless, which runs on plop, not here.
