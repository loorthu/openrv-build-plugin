#!/usr/bin/env bash
# List recent OpenRV refs and (optionally) check out / clone a chosen one.
#
# Two sub-commands:
#   list                                 -> emit JSON: {"tags":[...], "default_branch":"main", "current_dir":"...", "current_ref":"..."}
#   prepare <ref> [<target_dir>]         -> ensure $target_dir contains an OpenRV checkout at $ref.
#                                          If $target_dir already has rvcmds.sh, run `git fetch && git checkout $ref`.
#                                          Otherwise `git clone --recursive` upstream into $target_dir and check out $ref.
#                                          Prints final absolute path on stdout when done.

set -euo pipefail

UPSTREAM_URL="${OPENRV_UPSTREAM:-https://github.com/AcademySoftwareFoundation/OpenRV.git}"

cmd="${1:-list}"

case "$cmd" in
  list)
    here=""
    cur_ref=""
    if [ -f "./rvcmds.sh" ]; then
      here="$(pwd)"
      cur_ref="$(git -C "$here" describe --tags --always --dirty 2>/dev/null || git -C "$here" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
    fi

    # Fetch up to 10 most-recent semver-looking tags from upstream without needing a local clone.
    # `git ls-remote --tags --refs` returns lines like:
    #   <sha>\trefs/tags/v3.0.1
    raw_tags="$(git ls-remote --tags --refs "$UPSTREAM_URL" 2>/dev/null \
                | awk -F'refs/tags/' 'NF==2 {print $2}' \
                | grep -E '^v?[0-9]+(\.[0-9]+){1,3}([a-zA-Z0-9._-]*)?$' \
                | sort -V \
                | tail -n 10 \
                | awk '{ a[NR]=$0 } END { for (i=NR;i>=1;i--) print a[i] }')" || raw_tags=""

    python3 - "$here" "$cur_ref" <<'PY' "$raw_tags"
import json, sys
here, cur_ref = sys.argv[1], sys.argv[2]
raw = sys.argv[3] if len(sys.argv) > 3 else ""
tags = [line for line in raw.splitlines() if line.strip()]
print(json.dumps({
    "tags": tags,
    "default_branch": "main",
    "current_dir": here,
    "current_ref": cur_ref,
}))
PY
    ;;

  prepare)
    ref="${2:?usage: pick-openrv-version.sh prepare <ref> [<target_dir>]}"
    target="${3:-}"

    if [ -z "$target" ]; then
      if [ -f "./rvcmds.sh" ]; then
        target="$(pwd)"
      else
        target="$(pwd)/OpenRV"
      fi
    fi

    if [ -f "$target/rvcmds.sh" ]; then
      echo "[pick-openrv-version] Existing checkout at $target — fetching and checking out $ref" >&2
      git -C "$target" fetch --tags --recurse-submodules origin
      git -C "$target" checkout "$ref"
      git -C "$target" submodule update --init --recursive
    else
      mkdir -p "$(dirname "$target")"
      echo "[pick-openrv-version] Cloning $UPSTREAM_URL into $target (this will take a few minutes)..." >&2
      git clone --recursive "$UPSTREAM_URL" "$target"
      git -C "$target" fetch --tags
      git -C "$target" checkout "$ref"
      git -C "$target" submodule update --init --recursive
    fi

    cd "$target"
    pwd
    ;;

  *)
    echo "usage: pick-openrv-version.sh {list | prepare <ref> [<target_dir>]}" >&2
    exit 2
    ;;
esac
