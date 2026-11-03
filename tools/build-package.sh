#!/usr/bin/env sh
# Build the NEMESIS package (id: gen5.autolock) and the USB installer sticks.
#
#   dist/gen5-autolock-install.zip           ready-to-go installer: seeds DRY_RUN=0 (LIVE)
#   dist/gen5-autolock-install-testmode.zip  same package, seeds DRY_RUN=1 (log only)
#   dist/gen5.autolock.zip                   the bare LIVE package (for `nemesis install`
#                                            from a shell, or the Package Store)
#
# Each stick is NEMESIS.data (type=install) + gen5.autolock.zip at its root: extract it
# to the ROOT of a USB stick and insert. The mode comes from gen5-autolock.conf.seed,
# written here and copied to /data/nemesis/gen5-autolock.conf by the install hook on a
# fresh install only (an update keeps the user's config). The daemon's built-in default
# is DRY_RUN=1, so a missing config always fails safe.
# dist/ is gitignored. Uses `zip` if present, otherwise Python's zipfile.
#
# Alternative (NEMESIS's own builder): assemble the same tree and run
#   python3 tools/make_nemesis_package.py <tree> -o gen5.autolock.zip
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)      # repo root (this script lives in tools/)
DIST="$HERE/dist"
mkdir -p "$DIST"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- zip a directory (files at the zip root): prefer `zip`, else Python ---
zip_dir() { # <src-dir> <out-zip>
    rm -f "$2"
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

# --- stage the package tree with the given DRY_RUN seed and zip it ---
build_pkg() { # <dry_run 0|1> <out-zip>
    S="$TMP/pkg$1"; rm -rf "$S"; mkdir -p "$S/bin" "$S/scripts" "$S/ref"
    cp "$HERE/package/NEMESIS.data"       "$S/NEMESIS.data"
    cp "$HERE/walkaway.sh"                "$S/walkaway.sh"        # the daemon = service.0
    cp "$HERE/gen5-autolock.conf.example" "$S/gen5-autolock.conf.example"
    cp "$HERE/package/bin/toggle.sh"      "$S/bin/toggle.sh"      # app.0
    cp "$HERE/package/scripts/"*.sh       "$S/scripts/"
    cp "$HERE/ref/README.md"              "$S/ref/README.md"
    {
        cat "$HERE/gen5-autolock.conf.example"
        echo ""
        echo "# ---- set by the installer you chose: 0 = LIVE, 1 = TEST MODE. The GO LIVE /"
        echo "# ---- TEST MODE USB sticks change it; so does the custom-settings stick."
        echo "DRY_RUN=$1"
    } > "$S/gen5-autolock.conf.seed"
    zip_dir "$S" "$2"
}

# --- wrap a package zip into a USB install stick zip ---
build_stick() { # <pkg-zip> <out-zip>
    S="$TMP/stick-$(basename "$2" .zip)"; rm -rf "$S"; mkdir -p "$S"
    cp "$1" "$S/gen5.autolock.zip"
    {
        echo "[nemesis]"
        echo "version=1.0"
        echo "type=install"
        echo "path=gen5.autolock.zip"
    } > "$S/NEMESIS.data"
    zip_dir "$S" "$2"
}

build_pkg 0 "$DIST/gen5.autolock.zip"
build_stick "$DIST/gen5.autolock.zip" "$DIST/gen5-autolock-install.zip"
build_pkg 1 "$TMP/gen5.autolock-testmode.zip"
build_stick "$TMP/gen5.autolock-testmode.zip" "$DIST/gen5-autolock-install-testmode.zip"

echo "built: $DIST/gen5.autolock.zip                   (bare LIVE package: nemesis install / Package Store)"
echo "built: $DIST/gen5-autolock-install.zip          (USB installer — LIVE from the next stop)"
echo "built: $DIST/gen5-autolock-install-testmode.zip (USB installer — TEST MODE, log only)"
echo "inspect on the unit with:  nemesis pkg-info gen5.autolock.zip"
