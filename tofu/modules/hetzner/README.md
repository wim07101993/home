# `modules/hetzner`

Everything at Hetzner that has a Cloud API object: two servers, one volume,
one firewall, one Storage Box.

**Adoption only.** Nothing here is meant to create anything, ever — see the
root [`README.md`](../../README.md), "Why adoption and not `create`".
`prevent_destroy` is on every resource and is load-bearing: bumba is a `cpx11`,
which `fsn1` no longer sells.

Providers are inherited from the root module; this one configures none.
