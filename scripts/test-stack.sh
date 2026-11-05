#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test_valve_cache_config.py
while IFS= read -r script; do bash -n "$script"; done < <(git ls-files '*.sh')
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s installer/tests -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/sonar_tests -v
