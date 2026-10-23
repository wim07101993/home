# Tofu

Tofu contains all configuration for applications. 

## Prerequisits

- Tofu cli
- Bitwarden cli
- Tailscale vpn

## Deploy

### Setup env

Secrets are kept in Bitwarden. Tofu will require some secrets, so there are 2 scripts which can help to initialise the
environment: 

1. Unlock Bitwarden vault: `bw unlock`
2. Set Bitwarden session: `export BW_SESSION=<session value from bitwarden>`
3. Set up environment: `source env.sh`

### Actually deploy

1. Let tofu plan the changes: `tofu plan`
2. Validate the plan
3. Apply the plan: `tofu apply`

If any secrets were added/modified, also run `./bw-seed.sh` to ensure they are stored in Bitwarden as well. When adding
secrets, it is necessary to add those in the `bw-seed.sh` script as well.