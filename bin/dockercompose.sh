#!/bin/bash
set -euo pipefail

SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
PROJECTDIR="${SCRIPT%/*/*}"

export SOPS_AGE_KEY_FILE=/var/sops/age/keys.txt

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <docker compose arguments>" >&2
    exit 1
fi

envfiles="$PROJECTDIR/envfiles"
# Check if envfiles file exists
if [[ ! -f "$envfiles" ]]; then
    echo "Error: $envfiles not found" >&2
    exit 1
fi

cleanup() {
    rm -f "${tmpfiles[@]}" "${symlinks[@]}" 2>/dev/null
}
trap cleanup EXIT TERM INT

declare -a tmpfiles=()
declare -a symlinks=()

# Read envfiles from file (one per line)
while IFS= read -r fenc || [[ -n "$fenc" ]]; do
    # Remove .enc from filename
    f="${fenc%.enc.env}.env"

    tmpfile=$(mktemp --suffix=.env)
    tmpfiles+=("$tmpfile")

    symlink="$PROJECTDIR/$f"
    symlinks+=("$symlink")

    echo "Decrypting: $fenc -> $f" >&2
    sops --input-type dotenv --output-type dotenv -d "$PROJECTDIR/$fenc" > "$tmpfile"
    ln -s "$tmpfile" "$symlink"
done < "$envfiles"

echo "Decrypted ${#symlinks[@]} env file(s)" >&2

docker compose -f "$PROJECTDIR/docker-compose.yaml" "$@"
