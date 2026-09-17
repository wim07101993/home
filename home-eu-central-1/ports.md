# USED ports

Host ports published by the compose stacks and tofu modules in this directory.
Derived from the `ports:` lines, 2026-09-17 -- not from what might run here one
day.

| Port | Service                        |
|------|--------------------------------|
| 80   | reverse-proxy (traefik) http   |
| 443  | reverse-proxy (traefik) https  |
| 3001 | zitadel                        |
| 3002 | zitadel-login                  |
| 3005 | score-api                      |
| 3006 | score-web-app                  |
| 5432 | postgres                       |

The previous version of this file also listed immich (2283), it-tools (3000),
grafana (3003), loki (3004) and memo (3007). None of those run on bumba -- it
is a `cpx11` with 2 GB of RAM, which is why immich lives on mindy.

**5432 binds 0.0.0.0.** The only thing keeping postgres off the internet is
`firewall-1` (`10051212`), which allows 80, 443 and icmp and nothing else.
Narrowing the binding to localhost plus the tailnet address would make that two
layers instead of one -- see `tofu/README.md`.
