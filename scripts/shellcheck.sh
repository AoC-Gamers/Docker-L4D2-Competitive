#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mapfile -d '' -t scripts < <(git ls-files -z --cached --others --exclude-standard -- '*.sh')
"${SHELLCHECK:-shellcheck}" --shell=bash --severity=warning "${scripts[@]}"
