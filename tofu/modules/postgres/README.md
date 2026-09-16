# `modules/postgres`

Databases and (later) roles in bumba's postgres.

Two things deliberately absent:

- **`tofu_state`**, the role and the database. The backend connects as that
  role to read state; if this module managed it, the credential needed to read
  state would live inside state. Created by hand via
  [`bootstrap-state-db.sh`](../../bootstrap-state-db.sh) and left alone.
- **Roles generally**, for now. A role's password cannot be read back —
  postgres stores only a SCRAM hash — so an imported role lands in state with
  `password = ""` and the next plan proposes setting the live password to
  empty. Every adopted role needs `ignore_changes = [password]`.

Providers are inherited from the root module; this one configures none.
