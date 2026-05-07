#!/usr/bin/env bash
# Cross-platform "open this URL or file in the default handler".
# Usage: open-installer.sh <url-or-path>

set -eu
target="${1:?usage: open-installer.sh <url-or-path>}"

uname_s="$(uname -s 2>/dev/null || echo unknown)"
case "$uname_s" in
  Darwin)
    open "$target"
    ;;
  Linux)
    if command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$target" >/dev/null 2>&1 &
    else
      echo "xdg-open not available; please open this manually: $target" >&2
      exit 1
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    # `start` is a cmd.exe builtin; invoke via cmd
    cmd.exe /c start "" "$target"
    ;;
  *)
    echo "Unsupported OS for auto-open; please open this manually: $target" >&2
    exit 1
    ;;
esac
