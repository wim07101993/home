# Machine layer

NixOS owns the OS, packages and mounts. OpenTofu owns the containers, the
Hetzner objects and everything with an API -- see `../tofu` and
`../docs/iac-migration.md` for the boundary.

Nothing here configures a service. If you are looking for traefik, zitadel or
backrest, they are containers and they live in `../tofu`.

## Hosts

| host        | where          | boot | notable                                             |
|-------------|----------------|------|-----------------------------------------------------|
| `bumba`     | Hetzner cpx11  | BIOS | reverse proxy, zitadel, gatus, postgres             |
| `mindy`     | Hetzner        | BIOS | 100 GB volume `rafiki`; NFS client of samson        |
| `samson`    | home           | BIOS | 8.4 TiB btrfs RAID1, NFS server, smartd             |
| `plop`      | home           | BIOS | home-assistant, SkyConnect radio                    |
| `rehearsal` | Hetzner cx22   | BIOS | throwaway, bumba's config verbatim                  |

`rehearsal` exists because bumba's install must be done **in place**. `cpx11` is
no longer orderable, so bumba cannot be replaced by a new server and there is no
flip-back. The rehearsal is where the config is allowed to be wrong.

### disko only ever touches the OS disk

Every `disko.nix` here declares one device and no more. The 8.4 TiB RAID1 on
samson, its 4.5 TiB disks and 14 TB backup disk, mindy's Hetzner volume and the
Synology md/LVM/bcache leftovers on samson's nvme are all declared as plain
`fileSystems` entries instead, or not declared at all.

That split is the only thing standing between a typo and the media library.
disko formats what it is given.

**Devices are named by `/dev/disk/by-id/`, never `/dev/sdX`.** The letters are
assigned in probe order and move. On samson between 2026-10-03 and 2026-10-06 --
no hardware changed, the machine was just rebooted -- `/dev/sda` went from being
the OS disk to being devid 3 of the RAID1, and the OS SSD became `/dev/sde`. A
`disko.nix` naming `/dev/sda` would have formatted an array member. `rehearsal`
is the one exception, because that VM is created with a single disk and thrown
away.

### Still to do per host

`samson/hardware.nix` and `plop/hardware.nix` are **approximated, not
generated** -- the usual SATA/NVMe/USB module sets rather than what
`nixos-generate-config` observed. Both are physical machines; run it there and
reconcile before installing. The Hetzner hosts need none of this because
`qemuGuest` and virtio cover them.

## Deploying

```sh
# once, on the rehearsal VM
hcloud server create --name rehearsal --type cx22 --location fsn1 \
  --image debian-12 --ssh-key <key>

nix run github:nix-community/nixos-anywhere -- \
  --flake .#rehearsal root@<ip>
```

`nixos-anywhere` kexecs into an installer, partitions with disko and installs.
It **wipes the disk**. On bumba that means `/docker-volumes` has to be restored
afterwards -- 247 MB, so a tarball, not a data migration.

### Shift volume ownership after a restore

dockerd runs with `userns-remap`: root in a container is uid 165536 on the host,
and container uid N is host uid 165536+N. A tarball taken on a host without
remapping restores with the old ids, and the containers then cannot write their
own data -- postgres refuses to start on a data directory it does not own.

Shift every remapped service's directory once, after the restore and before the
first `tofu apply`. Skip `plex`, `homeassistant`, `filebrowser`, `backrest` and `navidrome`:
they set `userns_mode = "host"` and keep the real ids. The guard makes it safe
to run twice.

```sh
for d in /docker-volumes/*; do
  case "${d##*/}" in plex|homeassistant|filebrowser|backrest|navidrome) continue ;; esac
  find "$d" -print0 | while IFS= read -r -d '' f; do
    u=$(stat -c %u "$f"); g=$(stat -c %g "$f")
    [ "$u" -ge 165536 ] && continue
    chown -h "$((u + 165536)):$((g + 165536))" "$f"
  done
done
```

Tailscale is not authenticated declaratively. Run `tailscale up` once per host;
an auth key here would be a secret in a public repository.

## Things that bit us, recorded so they bite once

**bumba boots legacy BIOS.** `/sys/firmware/efi` is absent on the live host. The
Debian cloud image ships both a `bios_grub` partition and an ESP, so the
`/boot/efi` mount there proves nothing. Hetzner fixes the firmware mode at
creation. An EFI-only layout installs cleanly and then does not boot, and on a
server that cannot be reordered the only way back is the rescue console.

**Do not set `log-opts` in the docker daemon.** The OpenTofu docker provider's
`log_opts` is Optional and ForceNew but not Computed, so leaving it out asserts
"must be empty". A daemon that stamps `max-size`/`max-file` gives every container
a permanent replacement diff, and each replacement gets stamped again. samson ran
that way until 2026-09-30, and editing `daemon.json` was not enough to stop it --
`log-opts` is not in docker's SIGHUP-reloadable set, so the daemon needed a
restart.

Which leaves **log rotation unsolved on every host**. The options are per-container
`log_opts` in OpenTofu (replaces every container once) or switching the daemon to
the `journald` driver and letting `SystemMaxUse` bound it. Neither is done.

## Coupled to OpenTofu, so do not tidy unilaterally

**samson's array mountpoint.** It is still OMV's
`/srv/dev-disk-by-uuid-25d0f3ec-.../`, because tofu's plex module binds
`<array>/media` by that literal path. It is also the last service bind outside
`/docker-volumes`. Renaming it is a tofu change.

**plop's radio path.** tofu's home-assistant module passes `/dev/ttyUSB0`
straight through. That name is allocated in probe order and only happens to be
stable because it is the one USB serial device on the machine. `plop/default.nix`
adds a `/dev/zigbee` symlink as a safety net; pointing tofu at it is the fix.

**The SSH user.** NixOS hosts refuse root over SSH; logins go to `wim`, who has
passwordless sudo and is in the `docker` group. `../tofu/providers.tf` still
connects as `ssh://root@...`, which works against today's Debian/OMV hosts and
fails against a NixOS one. Switch each provider to `wim@` in the same change
that moves its host to NixOS. Deploy after install with
`nixos-rebuild switch --flake .#<host> --target-host wim@<host> --sudo`.

## Found while writing this, not acted on

**mindy's fstab has three dead NFS mounts** -- `/docker-volumes/kopia/data/{audio-archive,backups,media}`.
kopia is gone. Only the filebrowser `audio-archive` mount is live, and only that
one is carried over here.

**samson serves nothing over SMB.** OMV's `smb.conf` has a `[global]` section and
no shares, so there is nothing to port. NFS was doing all of it.

## Not managed here

Databasus's backup targets. They live in its own embedded postgres and there is
no provider for them, so the six entries are configured in its UI. The dumps and
`secret.key` are backed up by backrest; the target list is not. Write it down
before rebuilding anything that hosts it.
