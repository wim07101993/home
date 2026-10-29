# Home

This repository contains the configuration of my home-lab.

## Architecture

### Servers

| Server | Location | type      | Purpose                 | Backup                                    |
|:-------|:---------|:----------|:------------------------|:------------------------------------------|
| Samson | local    | NAS       | media libaray + backups | partially by mindy + external hard drives |
| Plop   | local    | Dedicated | local applications      | mindy                                     |
| Bumba  | cloud    | VPS       | High availability apps  | samson + mindy                            |
| Mindy  | cloud    | VPS       | Public applications     | samson                                    | 

### Backups

#### Configuration

All server configuration exists in git using OpenTofu and Nix. General rule of thumb is 
that everything should exist in tofu except when that is not possible (like hardware 
configurations, file systems,...). If it is not possible to configure in tofu, it should
exist in nix.

Laptop configurations only exist in nix.

#### Databases

All databases are backed up with databasus. All except the ones which are not supported,
mainly file-based databases like sqlite. These are backed up the same way all other files
are.

#### Files

How files are backed up depends on the server they are on. There are three storages:
samson (NAS), snow-white (a storage box at Hetzner) and a backup drive offline.

- All data is backed up to samson, except samson itself
- All data is backed up on snow-white, except the backups which are on samson
- Samson is entirely backed up on the offline drive

E.g.: Fotos of photos.wvl.app are stored in immich → mindy → rafiki volume. This data
is backed up in snow-white and samson. Samson does back these up every couple of months
on the offline-drive but does not back them up again to snow-white, since they are already
there.

All tofu modules which needs backups, define that in a `backup.tf` file which contains 
an output containing the mounts the backup:

```terraform
output "backup" {
  value = {
    mounts = { photos = var.library_path }
  }
}
```

