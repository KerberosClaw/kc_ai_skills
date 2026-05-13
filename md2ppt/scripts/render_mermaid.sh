#!/usr/bin/env bash
# md2ppt — mermaid render wrapper with content-hash caching.
#
# Usage:
#   render_mermaid.sh <input.mmd> [<output_dir>]
#
# Hashes the .mmd content; if PNG with that hash already exists, skip render.
# Output PNG path printed to stdout.

set -euo pipefail

INPUT="$1"
OUTDIR="${2:-$(dirname "$INPUT")/_assets}"
mkdir -p "$OUTDIR"

HASH=$(md5 -q "$INPUT" 2>/dev/null || md5sum "$INPUT" | awk '{print $1}')
HASH_SHORT="${HASH:0:10}"
PNG="$OUTDIR/diag_${HASH_SHORT}.png"

if [ ! -f "$PNG" ]; then
    mmdc -i "$INPUT" -o "$PNG" -t default -b white -w 1920 -H 1080 >/dev/null 2>&1 \
        || { echo "mmdc failed for $INPUT" >&2; exit 1; }
fi

echo "$PNG"
