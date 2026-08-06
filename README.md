# services-dockerskeleton

Skeleton for a Docker Compose service deployed on a systemd-managed host, with
secrets encrypted at rest via [SOPS](https://github.com/getsops/sops) and
conventional-commit tooling ([Commitizen](https://commitizen-tools.github.io/commitizen/)
+ [pre-commit](https://pre-commit.com/)) already wired up.

## Layout

```
bin/
  up.sh              # entrypoint: docker compose up -d with secrets decrypted
  dockercompose.sh   # decrypts secrets/*.enc, then runs `docker compose <args>`
  secret-edit.sh     # create/edit a secrets/*.enc via `sops edit`
docker-compose.yaml  # the actual service definition (fill this in)
.env                 # example env file: plain values + *_FILE secret references
secrets/
  *.enc              # SOPS-encrypted secrets, one value per file (committed)
.sops.yaml           # SOPS creation rule: encrypts secrets/*.enc with an age key
systemd/app.service  # unit template; symlink into /etc/systemd/system/
scripts/hooks/       # pre-commit hook scripts
.pre-commit-config.yaml
.cz.toml             # Commitizen config (conventional commits, bump, changelog)
```

## Setting up a new service from this skeleton

1. Fill in `docker-compose.yaml` with the real services/volumes.
2. Fill in the placeholders in `systemd/app.service`: `<APP NAME>`, `<USER>`,
   `<GROUP>`, `/opt/<app_path>`.
3. Update `.sops.yaml` with the deployment's actual `age` public key.
4. Symlink the unit and enable it:
   ```
   ln -s /opt/<app_path>/systemd/app.service /etc/systemd/system/app.service
   systemctl daemon-reload
   systemctl enable --now app.service
   ```

## Secrets

Real secrets never touch the repo in plaintext. Each secret is one encrypted
file under `secrets/`, and `.env` (committed, safe to read) tells services
where to find the decrypted value at runtime:

- **Unprotected** values (not secret) go straight into `.env` as normal
  `KEY=value` pairs.
- **Protected** values are referenced with a `*_FILE` key pointing at
  `/run/secrets/<name>`, e.g. `DB_PASSWORD_FILE=/run/secrets/db_password`.
  The app is expected to read the secret from that file path, not from an
  env var — this is the same convention Docker Swarm secrets and images
  like `postgres` use.

To create or edit a secret:

```
bin/secret-edit.sh db_password
```

This opens `$EDITOR` on the decrypted content of `secrets/db_password.enc`
(creating the file if it doesn't exist yet) and re-encrypts on save — the
secret value never touches shell history or a process argument list.

`.gitignore` allows `secrets/*.enc` but ignores everything else under
`secrets/`, so only encrypted files can ever be committed from that
directory.

### How it's decrypted at runtime

`bin/dockercompose.sh` (called by `bin/up.sh`, used as the systemd
`ExecStart`/`ExecReload`) does the following before invoking
`docker compose`:

1. Creates a private temp directory, `$SECRETS_DIR` (`mktemp -d`; the
   systemd unit sets `PrivateTmp=true`, so this is already isolated and
   cleaned up when the service stops).
2. Decrypts every `secrets/*.enc` into `$SECRETS_DIR/<name>` (`.enc` dropped),
   using the age key at `SOPS_AGE_KEY_FILE` (`/var/sops/age/keys.txt`).
3. Exports `$SECRETS_DIR` and runs `docker compose -f docker-compose.yaml "$@"`.

In `docker-compose.yaml`, bind-mount `$SECRETS_DIR` into each service that
needs secrets, at the path used by its `*_FILE` env vars:

```yaml
services:
  app:
    env_file: .env
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro
```

The temp directory (and the decrypted secrets in it) is removed on exit,
interrupt, or termination.

## Running locally

```
bin/up.sh          # docker compose up -d, with secrets decrypted first
bin/dockercompose.sh <any docker compose args>
```

Requires `sops`, `age`, and `docker compose` on `PATH`, plus a readable
`SOPS_AGE_KEY_FILE`.

## Development tooling

Commit hooks are managed by the `pre-commit` framework (installed into
`.git/hooks`, not a custom `core.hooksPath`). The `check-secrets` hook also
requires `jq` on `PATH`:

```
uv tool install pre-commit
uv tool install commitizen
pre-commit install --hook-type pre-commit --hook-type commit-msg --hook-type pre-push
```

- **pre-commit stage** — `scripts/hooks/pre-commit-checks.sh` blocks a commit
  if `secrets/*.enc` isn't genuine SOPS output, or if a `.env`/`.env.*` file
  contains a plaintext `PASS`/`SECRET`/`PASSPHRASE` value (`*_FILE` keys are
  exempt, since their value is a path, not the secret).
- **commit-msg / pre-push** — Commitizen enforces
  [Conventional Commits](https://www.conventionalcommits.org/) and validates
  branch naming.

Bumping a version (updates `.cz.toml`, `CHANGELOG.md`, creates an annotated
tag):

```
cz bump
```
