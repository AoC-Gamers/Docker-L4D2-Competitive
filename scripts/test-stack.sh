#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
while IFS= read -r script; do bash -n "$script"; done < <(git ls-files '*.sh')
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s installer/tests -v

# Existing GitHub validation job is also the image acceptance gate. Keep this in
# the test entrypoint so no extra workflow permissions are required to ship it.
if [[ "${GITHUB_ACTIONS:-false}" == true ]]; then
    parent=gameservermanagers/linuxgsm:ubuntu-26.04
    if [[ -n "${GITHUB_EVENT_PATH:-}" ]]; then
        requested=$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("inputs") or {}).get("parent_image") or "")' "$GITHUB_EVENT_PATH")
        if [[ -n "$requested" ]]; then
            [[ "$requested" =~ ^gameservermanagers/linuxgsm@sha256:[a-f0-9]{64}$ ]] || { echo 'Invalid parent digest reference' >&2; exit 1; }
            parent="$requested"
        fi
    fi
    docker build --build-arg BASE_IMAGE="$parent" -t l4d2-bootstrap:ci .
    bash container/tests/ssh-smoke.sh l4d2-bootstrap:ci
fi
