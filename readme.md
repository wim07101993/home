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

- Configuration is backed up in git
- Databases are backed up using Databasus
- Filesystem is backed up using Backrest (not entire media library)