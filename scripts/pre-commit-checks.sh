#!/bin/bash
# .githooks/pre-commit
set -euo pipefail

fail=0

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required for pre-commit secrets validation but was not found." >&2
    exit 1
fi

# --- Hook 1: secrets/*.enc must be valid SOPS JSON with 'data' + 'sops' at root ---
while IFS= read -r f; do
    [[ -z "$f" ]] && continue

    if ! jq empty "$f" >/dev/null 2>&1; then
        echo "ERROR: $f is not valid JSON." >&2
        fail=1
        continue
    fi

    has_data=$(jq 'has("data")' "$f")
    has_sops=$(jq 'has("sops")' "$f")
    has_mac=$(jq '.sops | has("mac")' "$f" 2>/dev/null || echo false)

    if [[ "$has_data" != "true" || "$has_sops" != "true" || "$has_mac" != "true" ]]; then
        echo "ERROR: $f is in secrets/ with a .enc name but doesn't look like real SOPS output (missing 'data', 'sops', or 'sops.mac')." >&2
        fail=1
    fi
done < <(git diff --cached --name-only --diff-filter=ACM -- 'secrets/*.enc')

# --- Hook 2: plain .env(.*) files must not contain obvious secrets ---
pattern='(?i)(PASS|SECRET|PASSPHRASE)[A-Z0-9_]*[[:space:]]*='

while IFS= read -r f; do
    [[ -z "$f" ]] && continue

    matches=$(grep -nP "$pattern" "$f" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        real=$(echo "$matches" | grep -P '=\s*\S' || true)
        if [[ -n "$real" ]]; then
            echo "ERROR: $f contains a key matching PASS/SECRET/PASSPHRASE with a non-empty value:" >&2
            echo "$real" >&2
            fail=1
        fi
    fi
done < <(git diff --cached --name-only --diff-filter=ACM -- '*.env' '*.env.*')

if [[ "$fail" -eq 1 ]]; then
    echo "" >&2
    echo "Commit blocked. Encrypt real secrets with sops and move them to secrets/*.enc." >&2
    exit 1
fi

exit 0
