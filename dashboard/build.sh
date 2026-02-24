#!/bin/bash
# Bundle all dashboard JSON data into a single JS file so index.html works without a server.
# Run this after generating/updating any data/*.json files.
# Data lives in personal-info/dashboard/data/ (gitignored).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_ROOT/personal-info/dashboard/data"
OUT="$SCRIPT_DIR/data.js"

if [ ! -d "$DATA_DIR" ]; then
  echo "No data directory found at $DATA_DIR — nothing to bundle."
  exit 0
fi

echo "// Auto-generated — do not edit. Run build.sh to regenerate." > "$OUT"
echo "const DATA_BUNDLE = {};" >> "$OUT"

count=0
for f in "$DATA_DIR"/*.json; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .json)
  echo "DATA_BUNDLE['$name'] = $(cat "$f");" >> "$OUT"
  count=$((count + 1))
done

echo "Built $OUT with $count files"
