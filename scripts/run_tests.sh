#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

status=0
for suite in test_load test_logic test_secret test_track test_eval; do
    file="$ROOT/tests/$suite.lua"
    [ -f "$file" ] || continue
    echo "== $suite =="
    if ! lua "$file"; then
        status=1
    fi
done
exit "$status"
