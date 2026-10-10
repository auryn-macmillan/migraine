#!/usr/bin/env bash
#
# Compute line coverage for the deployable `src/` tree from an lcov report and
# emit a shields.io "endpoint" JSON badge. Requires no external service.
#
# Usage: scripts/coverage-badge.sh [lcov-file] [output-json]
#
# Defaults: lcov.info  ->  badge/coverage.json

set -euo pipefail

LCOV="${1:-lcov.info}"
OUT="${2:-badge/coverage.json}"

python3 - "$LCOV" "$OUT" <<'PY'
import json
import os
import sys

lcov_path, out_path = sys.argv[1], sys.argv[2]

lines_found = 0
lines_hit = 0
in_src = False

with open(lcov_path, encoding="utf-8", errors="ignore") as fh:
    for raw in fh:
        line = raw.strip()
        if line.startswith("SF:"):
            in_src = line[3:].startswith("src/")
        elif in_src and line.startswith("LF:"):
            lines_found += int(line[3:])
        elif in_src and line.startswith("LH:"):
            lines_hit += int(line[3:])

pct = round(100.0 * lines_hit / lines_found, 1) if lines_found else 0.0

if pct >= 90:
    color = "brightgreen"
elif pct >= 80:
    color = "green"
elif pct >= 70:
    color = "yellowgreen"
elif pct >= 60:
    color = "yellow"
elif pct >= 50:
    color = "orange"
else:
    color = "red"

message = f"{pct:g}%"
badge = {"schemaVersion": 1, "label": "coverage", "message": message, "color": color}

os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(badge, fh)

print(f"src line coverage: {message} ({lines_hit}/{lines_found})")
PY
