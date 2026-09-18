# `modules/hetzner`

Everything at Hetzner that has a Cloud API object: two servers, one volume,
one firewall, one Storage Box.

**Adoption only.** Nothing here is meant to create anything, ever — see the
root [`README.md`](../../README.md), "Why adoption and not `create`".
`prevent_destroy` is on every resource and is load-bearing: bumba is a `cpx11`,
which `fsn1` no longer sells.

Providers are inherited from the root module; this one configures none.

## Naming

| kind | convention | current |
|---|---|---|
| servers | Studio 100 characters | `bumba`, `mindy` (and at home: `samson`, `plop`) |
| storage boxes | Disney princesses | `snow-white` |
| volumes | Disney side characters | `rafiki` |

Cloud-side names follow the convention; tofu resource addresses describe the
ROLE (`hcloud_volume.data`, `hcloud_storage_box.backups`), so a rename is a
one-line change and not a state move. Servers are the exception —
`hcloud_server.bumba` uses the character name, because for a server the
character *is* the role.
