#!/usr/bin/env bash
# Run OpenRV's rvbootstrap correctly. This wrapper exists because rvcmds.sh
# is interactive and uses zsh/bash aliases that don't expand in non-interactive
# subshells without help. The skill should call this script instead of trying
# to assemble the bash invocation by hand.
#
# Usage:
#   run-bootstrap.sh <openrv_dir> <vfx_year> [<qt_home>] [<build_type>]
#
# Args:
#   openrv_dir   absolute path to the OpenRV checkout (must contain rvcmds.sh)
#   vfx_year     one of CY2023, CY2024, CY2025, CY2026
#   qt_home      (optional) override QT_HOME — pass the path printed by
#                install-qt.sh if you installed Qt 6.8 for CY2026
#   build_type   (optional) Release (default) or Debug
#
# Behavior:
#   - cd's into <openrv_dir>
#   - exports RV_VFX_PLATFORM (so rvcmds.sh skips its select menu)
#   - exports QT_HOME if provided
#   - enables bash alias expansion (so `rvbootstrap` resolves)
#   - sources rvcmds.sh
#   - runs `rvbootstrap` in the FOREGROUND
#   - tees combined stdout+stderr to build.log inside the OpenRV checkout
#
# This script must run in the foreground. Do not use bash's `&` or any harness
# "run_in_background" flag — rvbootstrap may emit additional prompts and a
# stranded stdin will produce an infinite-loop log file.

set -u

openrv_dir="${1:?usage: run-bootstrap.sh <openrv_dir> <vfx_year> [<qt_home>] [<build_type>]}"
vfx_year="${2:?usage: run-bootstrap.sh <openrv_dir> <vfx_year> [<qt_home>] [<build_type>]}"
qt_home="${3:-}"
build_type="${4:-Release}"

# --- validate -------------------------------------------------------------

if [ ! -d "$openrv_dir" ]; then
  echo "[run-bootstrap] not a directory: $openrv_dir" >&2
  exit 2
fi
if [ ! -f "$openrv_dir/rvcmds.sh" ]; then
  echo "[run-bootstrap] $openrv_dir does not contain rvcmds.sh" >&2
  exit 2
fi

case "$vfx_year" in
  CY2023|CY2024|CY2025|CY2026) ;;
  *)
    echo "[run-bootstrap] vfx_year must be one of CY2023, CY2024, CY2025, CY2026 (got: $vfx_year)" >&2
    exit 2
    ;;
esac

case "$build_type" in
  Release|Debug) ;;
  *)
    echo "[run-bootstrap] build_type must be Release or Debug (got: $build_type)" >&2
    exit 2
    ;;
esac

# --- run ------------------------------------------------------------------

cd "$openrv_dir"

export RV_VFX_PLATFORM="$vfx_year"
[ -n "$qt_home" ] && export QT_HOME="$qt_home"
export INIT_BUILD_TYPE="$build_type"

# macOS SDK consistency. If full Xcode is selected via xcode-select but xcrun
# (without -sdk macosx) resolves to the CommandLineTools SDK, shiboken/clang
# pick up CLT headers that may reference clang intrinsics (e.g. __builtin_ctzg)
# missing from the toolchain bundled with the chosen SDK, and PySide6 binding
# compiles fail. Force DEVELOPER_DIR and SDKROOT to Xcode's, and unset
# MACOSX_DEPLOYMENT_TARGET so OpenRV's CMake decides the deployment target.
if [ "$(uname -s)" = "Darwin" ]; then
  if xcode_dev="$(xcode-select -p 2>/dev/null)" && [ -n "$xcode_dev" ] \
     && [ "${xcode_dev#*Xcode.app/}" != "$xcode_dev" ]; then
    export DEVELOPER_DIR="$xcode_dev"
    if sdk_path="$(xcrun -sdk macosx --show-sdk-path 2>/dev/null)" && [ -n "$sdk_path" ]; then
      export SDKROOT="$sdk_path"
    fi
  fi
  unset MACOSX_DEPLOYMENT_TARGET
fi

# Aliases (rvbootstrap, rvsetup, rvcfg, rvbuild, rvmk, rvrelease, rvdebug) are
# defined in rvcmds.sh and not expanded in non-interactive bash subshells
# without this. zsh expands aliases in non-interactive subshells by default,
# but we use bash for portability.
shopt -s expand_aliases

log="$openrv_dir/build.log"

echo "[run-bootstrap] cwd=$openrv_dir"
echo "[run-bootstrap] RV_VFX_PLATFORM=$RV_VFX_PLATFORM"
[ -n "${QT_HOME:-}" ] && echo "[run-bootstrap] QT_HOME=$QT_HOME"
[ -n "${DEVELOPER_DIR:-}" ] && echo "[run-bootstrap] DEVELOPER_DIR=$DEVELOPER_DIR"
[ -n "${SDKROOT:-}" ] && echo "[run-bootstrap] SDKROOT=$SDKROOT"
echo "[run-bootstrap] INIT_BUILD_TYPE=$INIT_BUILD_TYPE"
echo "[run-bootstrap] full output also being written to $log"
echo "[run-bootstrap] ----- sourcing rvcmds.sh -----"

# Source rvcmds.sh and immediately invoke rvbootstrap. We pipe the combined
# output through tee so the user sees it AND we keep a log on disk. PIPESTATUS
# is used so the exit status reflects rvbootstrap's status, not tee's.
{ set +u; source ./rvcmds.sh && rvbootstrap; } 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

echo
if [ "$status" -eq 0 ]; then
  echo "[run-bootstrap] rvbootstrap succeeded."
else
  echo "[run-bootstrap] rvbootstrap exited with status $status. See $log for full output."
  echo "[run-bootstrap] tip: run 'rverrsummary' inside an interactive 'rvenv' shell for a quick error summary."
fi
exit "$status"
