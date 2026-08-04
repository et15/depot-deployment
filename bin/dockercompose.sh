#!/bin/bash
set -euo pipefail

SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
PROJECTDIR="${SCRIPT%/*/*}"

export SOPS_AGE_KEY_FILE=/var/sops/age/keys.txt

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <docker compose arguments>" >&2
    exit 1
fi

args=$(printf '%q ' "$@")
sops exec-env "$PROJECTDIR/.enc.env" "docker compose -f $PROJECTDIR/docker-compose.yaml $args"
