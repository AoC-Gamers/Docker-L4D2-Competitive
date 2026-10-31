#!/bin/bash
set -euo pipefail

# Runtime checks are advisory. Image builds use --strict to reject missing files.
strict=false
case "${1:-}" in
    --strict) strict=true ;;
    "") ;;
    *) printf 'Usage: %s [--strict]\n' "$0" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { printf 'Usage: %s [--strict]\n' "$0" >&2; exit 2; }

manifest="$(dirname "${BASH_SOURCE[0]}")/../runtime-packages.txt"
problems=0
checked=0

warn() {
    printf 'WARNING: %s\n' "$*" >&2
    problems=$((problems + 1))
}

printf 'Checking runtime dependencies (read-only)...\n'
if [[ ! -r "$manifest" ]]; then
    warn "Cannot read required package manifest: $manifest"
else
    while IFS= read -r package || [[ -n "$package" ]]; do
        [[ -n "$package" && "$package" != \#* ]] || continue
        checked=$((checked + 1))
        status="$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)"
        if [[ "$status" != installed ]]; then
            warn "Missing required package: $package"
            continue
        fi
        if ! files="$(dpkg-query -L "$package" 2>/dev/null)"; then
            warn "Cannot inspect library files for package: $package"
            continue
        fi
        # Inspect actual files too: layers can lose files while dpkg still says installed.
        while IFS= read -r path; do
            case "$path" in
                *.so|*.so.*)
                    [[ -e "$path" ]] || warn "Missing library file ($package): $path"
                    ;;
            esac
        done <<< "$files"
    done < "$manifest"
    [[ "$checked" -gt 0 ]] || warn "Required package manifest is empty"
fi

if [[ "$problems" -eq 0 ]]; then
    printf 'Libraries verified: %d required packages and their library files are present.\n' "$checked"
else
    printf 'WARNING: Libraries not verified: %d problem(s). Rebuild the image with its required dependencies.\n' "$problems" >&2
    if [[ "$strict" == true ]]; then exit 1; fi
fi
