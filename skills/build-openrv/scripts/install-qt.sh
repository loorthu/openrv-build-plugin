#!/usr/bin/env bash
# Install Qt headlessly via aqtinstall (https://github.com/miurahr/aqtinstall),
# which downloads Qt without needing a Qt account.
#
# Defaults are tuned for OpenRV CY2024: Qt 6.5.3 with the modules OpenRV needs.
# OpenRV expects Qt at $QT_HOME (e.g. ~/Qt/6.5.3/<platform>) so this script
# installs into ~/Qt by default to match the documented layout.
#
# Usage:
#   install-qt.sh [--version 6.5.3] [--modules qtwebengine,qtwebsockets,qtmultimedia,qtwebchannel,qtpositioning] [--dest ~/Qt]
#
# After completion prints the resolved QT_HOME path on stdout (suitable for `export QT_HOME=$(install-qt.sh ...)`).
#
# Note: qtdeclarative is intentionally NOT in the default modules — for Qt 6.5.3
# it is part of base Qt, not a selectable add-on, and aqt rejects it.

set -euo pipefail

version="6.5.3"
modules="qtwebengine,qtwebsockets,qtmultimedia,qtwebchannel,qtpositioning,qtimageformats,qt5compat"
dest="$HOME/Qt"

while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --modules) modules="$2"; shift 2 ;;
    --dest)    dest="$2";    shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Determine target_id (host) and arch_id for aqt
uname_s="$(uname -s 2>/dev/null || echo unknown)"
uname_m="$(uname -m 2>/dev/null || echo unknown)"

case "$uname_s" in
  Darwin)
    host="mac"
    target="desktop"
    arch="clang_64"
    expected_subdir="macos"
    ;;
  Linux)
    host="linux"
    target="desktop"
    arch="gcc_64"
    expected_subdir="gcc_64"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    host="windows"
    target="desktop"
    arch="win64_msvc2019_64"
    expected_subdir="msvc2019_64"
    ;;
  *)
    echo "Unsupported OS: $uname_s" >&2
    exit 1
    ;;
esac

# aqtinstall lives in pip; ensure it's available
if ! command -v aqt >/dev/null 2>&1; then
  if command -v pip3 >/dev/null 2>&1; then
    pip3 install --user aqtinstall
  elif command -v pip >/dev/null 2>&1; then
    pip install --user aqtinstall
  else
    echo "neither pip nor pip3 available; install Python 3 first" >&2
    exit 1
  fi
  # ensure user-local pip bin on PATH for this run
  for d in "$HOME/Library/Python/3.11/bin" "$HOME/Library/Python/3.12/bin" "$HOME/.local/bin"; do
    [ -d "$d" ] && PATH="$d:$PATH"
  done
  export PATH
fi

mkdir -p "$dest"

echo "[install-qt] aqt install-qt $host $target $version $arch -m $modules -O $dest" >&2
# shellcheck disable=SC2086
aqt install-qt "$host" "$target" "$version" "$arch" \
  -m $(echo "$modules" | tr ',' ' ') \
  -O "$dest"

resolved="$dest/$version/$expected_subdir"
if [ ! -d "$resolved" ]; then
  echo "Qt install completed but expected directory $resolved was not created. Check aqt output above." >&2
  exit 1
fi

echo "$resolved"
