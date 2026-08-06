#!/bin/bash
set -euo pipefail

SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
PROJECTDIR="${SCRIPT%/*/*}"

export SOPS_AGE_KEY_FILE=/var/sops/age/keys.txt

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <docker compose arguments>" >&2
    exit 1
fi

SECRETS_DIR=$(mktemp -d)
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
    chmod 400 "$SECRETS_DIR/$f"
    count=$((count + 1))
done

echo "Decrypted $count secret(s) into $SECRETS_DIR" >&2

export SECRETS_DIR
docker compose -f "$PROJECTDIR/docker-compose.yaml" "$@"
