#!/bin/bash
set -euo pipefail

# World-readable: the container reading a secret runs as whatever UID its
# image defaults to, almost never the UID running this script. $SECRETS_DIR
# is still ephemeral, removed on exit, and bind-mounted read-only.
SECRETS_DIR_MODE=755
SECRET_FILE_MODE=444
# Ownership to apply to $SECRETS_DIR and its contents, e.g. "1000:1000" or
# "appuser:appgroup". Empty (default) leaves ownership as whoever ran this
# script (root, under systemd) -- the chmod above already covers read access.
SECRETS_OWNER="${SECRETS_OWNER:-}"

SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
PROJECTDIR="${SCRIPT%/*/*}"

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-/var/sops/age/keys.txt}"

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <docker compose arguments>" >&2
    exit 1
fi

SECRETS_DIR=$(mktemp -d)
chmod "$SECRETS_DIR_MODE" "$SECRETS_DIR"
[[ -n "$SECRETS_OWNER" ]] && chown "$SECRETS_OWNER" "$SECRETS_DIR"
cleanup() {
    rm -rf "$SECRETS_DIR"
}
trap cleanup EXIT TERM INT

# Decrypt every secrets/*.enc into $SECRETS_DIR/<name> (same name, .enc dropped).
# $SECRETS_DIR is bind-mounted into containers at a common path (e.g. /run/secrets)
# and referenced from .env via *_FILE keys, e.g. DB_PASSWORD_FILE=/run/secrets/db_password
shopt -s nullglob
count=0
for fenc in "$PROJECTDIR"/secrets/*.enc; do
    f="$(basename "${fenc%.enc}")"

    echo "Decrypting: secrets/$(basename "$fenc") -> \$SECRETS_DIR/$f" >&2
    sops --input-type binary --output-type binary -d "$fenc" > "$SECRETS_DIR/$f"
    chmod "$SECRET_FILE_MODE" "$SECRETS_DIR/$f"
    [[ -n "$SECRETS_OWNER" ]] && chown "$SECRETS_OWNER" "$SECRETS_DIR/$f"
    count=$((count + 1))
done

echo "Decrypted $count secret(s) into $SECRETS_DIR" >&2

export SECRETS_DIR
docker compose -f "$PROJECTDIR/docker-compose.yaml" "$@"
