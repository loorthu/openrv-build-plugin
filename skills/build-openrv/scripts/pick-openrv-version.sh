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

    # Windows path-length pre-flight. The build tree nests ~150-200 chars deep
    # under <target>; total path must stay under Windows' legacy 260-byte
    # MAX_PATH limit (254 usable per OpenRV docs/build_system/config_windows.md).
    # Refuse to clone into a target that's already too long — the build will
    # fail in PySide6 hours from now and the user will have to move it anyway.
    case "$(uname -s 2>/dev/null)" in
      MINGW*|MSYS*|CYGWIN*)
        # Convert target to Windows form for accurate character count.
        win_target="$( (cd "$(dirname "$target")" 2>/dev/null && pwd -W 2>/dev/null) || echo "$target" )"
        if [ -n "$win_target" ] && [ "$win_target" != "$target" ]; then
          win_target="$win_target/$(basename "$target")"
        else
          win_target="$target"
        fi
        # Strip MSYS-style /c/ prefix for length calc if pwd -W wasn't available
        case "$win_target" in
          /[a-zA-Z]/*)
            d="${win_target#/}"; d="${d%%/*}"
            rest="${win_target#/[a-zA-Z]}"
            win_target="${d}:${rest}"
            ;;
        esac
        path_len=${#win_target}
        case "$win_target" in
          [A-Za-z]:[/\\]*) is_drive_path="yes" ;;
          *)               is_drive_path="no"  ;;
        esac
        if [ "$is_drive_path" = "no" ] || [ "$path_len" -gt 40 ]; then
          cat >&2 <<EOF

[pick-openrv-version] Refusing to prepare OpenRV checkout at:
  $win_target ($path_len chars)

Windows has a 254-byte path-length limit. OpenRV's build tree nests
150-200 chars deep, so the checkout path itself must be short — ideally
on a drive root like C:\\OpenRV (9 chars). If we cloned here, the build
would fail in PySide6 with 'cannot open file ... too long' hours from
now and you'd have to move it anyway.

Re-run with an explicit short target:
  pick-openrv-version.sh prepare $ref C:\\OpenRV

Or close this shell, launch a new MSYS2 MinGW64 shell with 'cd /c' (or
your chosen short root), and start Claude Code from there before re-running
/openrv-build:build.

EOF
          exit 4
        fi
        ;;
    esac

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
