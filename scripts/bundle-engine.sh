#!/bin/bash
# Builds the self-contained engine that ships inside Batteri.app: a private copy of Python
# with the batteri command-line tool installed into it. Nothing has to be installed on the
# user's Mac.
#
#   scripts/bundle-engine.sh <destination-directory>
#
# ENGINE_SOURCE picks what to install: a local checkout (default ../batteri when it exists)
# or any pip requirement, e.g. git+https://github.com/gunnarr/batteri@<commit>.
set -euo pipefail

DEST="${1:?usage: bundle-engine.sh <destination-directory>}"
PYTHON_VERSION="${PYTHON_VERSION:-3.13}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PINNED_ENGINE="$(cat "$HERE/engine.version")"

if [ -z "${ENGINE_SOURCE:-}" ]; then
  if [ -f "$HERE/../batteri/pyproject.toml" ]; then
    ENGINE_SOURCE="$HERE/../batteri"
  else
    ENGINE_SOURCE="git+https://github.com/gunnarr/batteri@$PINNED_ENGINE"
  fi
fi

command -v uv >/dev/null || { echo "uv is required: brew install uv" >&2; exit 1; }

# A relocatable Python build (python-build-standalone), not Homebrew's or the system's.
uv python install "$PYTHON_VERSION" >/dev/null
PY="$(uv python find --python-preference only-managed "$PYTHON_VERSION")"
ROOT="$(cd "$(dirname "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$PY")")/.." && pwd)"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$ROOT" "$DEST/python"

echo "Installing engine from $ENGINE_SOURCE"
uv pip install --quiet --python "$DEST/python/bin/python3" --break-system-packages \
  --no-cache --link-mode copy "$ENGINE_SOURCE"

# Drop what the engine never uses: GUI toolkits, the test suite, headers and build helpers.
LIB="$(echo "$DEST"/python/lib/python3.*)"
rm -rf "$LIB"/{test,idlelib,tkinter,turtledemo,ensurepip,pydoc_data,lib2to3,config-*} \
       "$LIB"/site-packages/{pip,pip-*,setuptools,setuptools-*} \
       "$DEST"/python/lib/{tcl*,tk*,itcl*,thread*,libtcl*,libtk*,pkgconfig} \
       "$DEST"/python/{include,share}
find "$DEST/python/bin" -mindepth 1 \( ! -name 'python3*' -o -name '*-config' \) -delete
find "$DEST" -name '__pycache__' -type d -prune -exec rm -rf {} +
find "$DEST" -name '*.a' -delete

# Compile ahead of time, so the engine starts quickly and never has to write into the
# signed app bundle. unchecked-hash: the bytecode is trusted without comparing timestamps.
"$DEST/python/bin/python3" -I -B -m compileall -q --invalidation-mode unchecked-hash "$LIB" >/dev/null || true

"$DEST/python/bin/python3" -I -B -m batteri --help >/dev/null
echo "Engine ready: $(du -sh "$DEST" | cut -f1)"
