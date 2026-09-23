# `modules/services/plex`

Plex Media Server on samson, serving the array at
`/srv/dev-disk-by-uuid-25d0.../media` (8.5 TB used of 11 TB).

## Cut over, do not import

The live container carries `com.docker.compose.*` labels from a Portainer
stack (`com.docker.compose.project=plex`, config at `/data/compose/1`).
`docker_container` cannot reproduce those, so an import would plan a recreate
anyway.

**Delete the stack in Portainer first.** Leave it and two systems manage one
container name — Portainer redeploys it, tofu plans it back, and whichever ran
last wins. That is the shape of the 2026-08 incident.

```
Portainer on samson -> Stacks -> plex -> Delete
tofu apply
```

## Drift this migration closes

`samson/plex/docker-compose.yaml` in this repo pinned `1.43.3.10896`. **That
tag does not exist.** Plex's tags carry a build suffix — the real one is
`1.43.3.10896-cb3ebc72d` — so that file could never have deployed, and the
stack ran `plexinc/pms-docker:latest` instead, resolving to
`1.43.2.10687-563d026ea`.

The file and the deployment had been describing different things, and the only
reason it never broke is that nobody redeployed the stack. The first apply of
this module found it immediately:

```
manifest for plexinc/pms-docker:1.43.3.10896 not found: manifest unknown
```

The module pins `1.43.2.10687-563d026ea`, the version that was actually
running. Upgrading to `1.43.4.10903-e5521bd8c` is a one-line change, worth
doing on its own rather than inside a migration.

## `network_mode = "host"`

Not a style choice. Plex's client discovery uses GDM broadcasts on
32410-32414/udp and DLNA on 1900/udp, none of which survive a bridge network.
The 32400 you see published is a consequence of host mode, not a `ports` block
— there is none.

## The config directory is not backed up

`/docker-volumes/plex` is 14 GB: the library database, metadata, and
thumbnails. It is the only part of this service that is not reproducible from
the media files — losing it means a full re-scan and the loss of watch state,
playlists and collections.

kopia snapshots `/export/media` (the media itself, which is also the part that
could be re-acquired) and does **not** snapshot `/docker-volumes/plex`. That is
the wrong way round, and predates this module.
