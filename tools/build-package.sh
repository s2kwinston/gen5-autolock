#!/usr/bin/env sh
# Build the installable NEMESIS package zip (id: gen5.autolock) from this repo.
# Assembles the package tree from the canonical walkaway.sh + the package/ folder,
# then zips it (paths relative to the package root). Output: dist/gen5.autolock.zip
# (dist/ is gitignored). Uses `zip` if present, otherwise Python's zipfile.
# Also builds dist/gen5-autolock-install.zip: a ready USB stick (NEMESIS.data
# type=install + the package zip) — extract it to the ROOT of a USB stick and insert.
#
# Alternative (NEMESIS's own builder): assemble the same tree and run
#   python3 tools/make_nemesis_package.py <tree> -o gen5.autolock.zip
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)      # repo root (this script lives in tools/)
OUT=${1:-"$HERE/dist/gen5.autolock.zip"}
STICK_OUT="${OUT%/*}/gen5-autolock-install.zip"
mkdir -p "${OUT%/*}"

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

rm -f "$OUT" "$STICK_OUT"

# --- zip a directory (files at the zip root): prefer `zip`, else Python ---
zip_dir() { # <src-dir> <out-zip>
    if command -v zip >/dev/null 2>&1; then
        ( cd "$1" && zip -q -r -X "$2" . )
        return
    fi
    # find a Python that actually runs (skip the Windows Store stub, which errors);
    # $PYTHON overrides, and `uv run python` is the last resort (a uv-managed box).
    PY=""
    for c in "${PYTHON:-}" python3 python "uv run --no-project python"; do
        [ -n "$c" ] || continue
        if $c -c "import sys" >/dev/null 2>&1; then PY=$c; break; fi
    done
    [ -n "$PY" ] || { echo "error: need 'zip', a working Python on PATH, or PYTHON=<interpreter> to build the zip" >&2; exit 1; }
    $PY - "$1" "$2" <<'PYEOF'
import sys, os, zipfile
stage, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _dirs, files in os.walk(stage):
        for f in sorted(files):
            full = os.path.join(root, f)
            arc = os.path.relpath(full, stage).replace(os.sep, "/")
            z.write(full, arc)
PYEOF
}

zip_dir "$STAGE" "$OUT"
echo "built: $OUT"
echo "inspect on the unit with:  nemesis pkg-info $(basename "$OUT")"

# --- the USB install stick: NEMESIS.data (type=install) + the package zip ---
STICK=$(mktemp -d)
trap 'rm -rf "$STAGE" "$STICK"' EXIT
cp "$OUT" "$STICK/$(basename "$OUT")"
{
    echo "[nemesis]"
    echo "version=1.0"
    echo "type=install"
    echo "path=$(basename "$OUT")"
} > "$STICK/NEMESIS.data"
zip_dir "$STICK" "$STICK_OUT"
echo "built: $STICK_OUT   (extract to the root of a USB stick, insert, tap Yes)"
