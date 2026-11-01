#!/usr/bin/env sh
# Build the installable NEMESIS package zip (id: gen5.autolock) from this repo.
# Assembles the package tree from the canonical walkaway.sh + the package/ folder,
# then zips it (paths relative to the package root). Output: gen5.autolock.zip
# (gitignored). Uses `zip` if present, otherwise Python's zipfile.
#
# Alternative (NEMESIS's own builder): assemble the same tree and run
#   python3 tools/make_nemesis_package.py <tree> -o gen5.autolock.zip
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-"$HERE/gen5.autolock.zip"}

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# --- assemble the package tree ---
cp "$HERE/package/NEMESIS.data"       "$STAGE/NEMESIS.data"
cp "$HERE/walkaway.sh"                "$STAGE/walkaway.sh"        # the daemon = service.0
cp "$HERE/gen5-autolock.conf.example" "$STAGE/gen5-autolock.conf.example"
mkdir -p "$STAGE/bin" "$STAGE/scripts" "$STAGE/ref"
cp "$HERE/package/bin/toggle.sh"      "$STAGE/bin/toggle.sh"      # app.0
cp "$HERE/package/scripts/"*.sh       "$STAGE/scripts/"
cp "$HERE/ref/README.md"              "$STAGE/ref/README.md"

rm -f "$OUT"

# --- zip it: prefer `zip`, else Python ---
if command -v zip >/dev/null 2>&1; then
    ( cd "$STAGE" && zip -q -r -X "$OUT" . )
else
    # find a Python that actually runs (skip the Windows Store stub, which errors)
    PY=""
    for c in python3 python; do
        if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys" >/dev/null 2>&1; then PY=$c; break; fi
    done
    [ -n "$PY" ] || { echo "error: need 'zip' or a working Python on PATH to build the zip" >&2; exit 1; }
    "$PY" - "$STAGE" "$OUT" <<'PYEOF'
import sys, os, zipfile
stage, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _dirs, files in os.walk(stage):
        for f in sorted(files):
            full = os.path.join(root, f)
            arc = os.path.relpath(full, stage).replace(os.sep, "/")
            z.write(full, arc)
PYEOF
fi
echo "built: $OUT"
echo "inspect on the unit with:  nemesis pkg-info $(basename "$OUT")"
