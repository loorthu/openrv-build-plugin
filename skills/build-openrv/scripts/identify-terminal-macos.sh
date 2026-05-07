#!/usr/bin/env bash
# Identify the macOS .app that hosts the current shell session by walking up
# the process tree from $PPID. Prints the .app name (e.g. "Ghostty.app",
# "iTerm.app", "Terminal.app", "Code.app") on stdout, or "unknown" if no .app
# ancestor is found within 12 hops.
#
# This is used to give the user a specific name when telling them to grant
# App Management permission, instead of a vague "your terminal app".

set -u

[ "$(uname -s)" = "Darwin" ] || { echo "unknown"; exit 0; }

pid="$PPID"
i=0
while [ "$i" -lt 12 ]; do
  i=$((i + 1))
  [ -z "$pid" ] && break
  [ "$pid" = "1" ] && break
  cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
  if [ -n "$cmd" ]; then
    # Take the OUTERMOST .app segment in the command path. Helper bundles like
    # "Code Helper (Plugin).app" live inside their parent's .app/Contents/
    # Frameworks/, so the path contains multiple .app segments. The outer one
    # (e.g. "Visual Studio Code.app") is what the user grants permissions to.
    app="$(printf '%s\n' "$cmd" | grep -oE '/[^/]+\.app/' | head -1 | tr -d '/')"
    if [ -n "$app" ]; then
      echo "$app"
      exit 0
    fi
  fi
  next_pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
  if [ -z "$next_pid" ] || [ "$next_pid" = "$pid" ]; then
    break
  fi
  pid="$next_pid"
done

echo "unknown"
