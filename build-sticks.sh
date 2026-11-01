#!/usr/bin/env sh
# Build a ready-to-use zip for each USB stick under usb-sticks/, for attaching to
# a GitHub Release. Each zip holds that stick's files AT ITS ROOT, so a user just
# extracts it to the top level of a USB stick and inserts it. Uses `zip` if present,
# else Python. Output: gen5-autolock-<name>.zip (gitignored).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)

zip_dir() { # <src-dir> <out-zip>
    src=$1; out=$2; rm -f "$out"
    if command -v zip >/dev/null 2>&1; then
        ( cd "$src" && zip -q -r -X "$out" . )
    else
        PY=""
        for c in python3 python; do
            if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys" >/dev/null 2>&1; then PY=$c; break; fi
        done
        [ -n "$PY" ] || { echo "error: need 'zip' or a working Python on PATH" >&2; exit 1; }
        "$PY" - "$src" "$out" <<'PYEOF'
import sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _d, files in os.walk(src):
        for f in sorted(files):
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, src).replace(os.sep, "/"))
PYEOF
    fi
    echo "built: $out"
}

for d in "$HERE"/usb-sticks/*/; do
    name=$(basename "$d")
    zip_dir "$d" "$HERE/gen5-autolock-$name.zip"
done
echo "Attach these to the GitHub Release alongside gen5.autolock.zip (the installer)."
