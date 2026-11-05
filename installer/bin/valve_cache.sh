#!/bin/bash
set -euo pipefail
# Shared implementation inherited by AoC and Vanilla; no Docker socket required.
exec python3 "${DIR_INSTALLER_LIB:-$(dirname "${BASH_SOURCE[0]}")/../lib}/valve_cache.py" "$@"
