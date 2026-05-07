#!/usr/bin/env bash
# Idempotently install OpenRV build dependencies on Windows. Run from MSYS2 MinGW64 bash.
#
# Usage:
#   install-deps-windows.sh                # all auto-installable items; prompts on UAC
#   install-deps-windows.sh --only <name>  # just one item
#   install-deps-windows.sh --elevated     # skip confirmations
#
# winget commands need an admin shell. If not running as admin, the user will
# get a UAC prompt for each install — there is no headless workaround for this
# unless Claude Code is launched with bypass-permissions and the parent shell
# is admin.

set -euo pipefail

ELEVATED=false
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --elevated) ELEVATED=true; shift ;;
    --only)     ONLY="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

confirm() {
  $ELEVATED && return 0
  printf '%s [y/N] ' "$1" >&2
  read -r ans
  case "$ans" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac
}

want() {
  [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]
}

run_winget() {
  if command -v winget >/dev/null 2>&1; then
    echo "[install-deps] winget $*"
    winget "$@" --accept-source-agreements --accept-package-agreements
  else
    echo "[install-deps] winget not available; falling back to chocolatey if available." >&2
    return 1
  fi
}

run_choco() {
  if command -v choco >/dev/null 2>&1; then
    echo "[install-deps] choco $*"
    choco "$@" -y
  else
    echo "[install-deps] choco not available." >&2
    return 1
  fi
}

# --- helpers ---------------------------------------------------------------

install_pacman_pkgs() {
  echo "[install-deps] pacman -Sy --needed --noconfirm $*"
  pacman -Sy --needed --noconfirm "$@"
}

install_vs2022_buildtools() {
  # MSVC v143 14.40 specifically (Boost needs 14.39 separately for some builds; advanced users can add).
  run_winget install --id Microsoft.VisualStudio.2022.BuildTools \
    --override "--add Microsoft.VisualStudio.Component.VC.14.40.17.10.x86.x64 --add Microsoft.VisualStudio.Workload.VCTools --quiet --wait" \
    || true
}

install_cmake() {
  run_choco install cmake --installargs '"ADD_CMAKE_TO_PATH=System"' \
    || run_winget install --id Kitware.CMake
}

install_python() {
  run_winget install --id Python.Python.3.11 \
    || run_choco install python --version=3.11.9
}

install_perl() {
  run_choco install strawberryperl
}

install_rust() {
  run_winget install --id Rustlang.Rustup \
    || run_choco install rustup.install
}

install_sccache() {
  if command -v cargo >/dev/null 2>&1; then
    cargo install sccache
  else
    run_winget install --id Mozilla.sccache || run_choco install sccache
  fi
}

install_qt() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  bash "$script_dir/install-qt.sh"
}

# --- main ------------------------------------------------------------------

# MSYS2 packages
MSYS2_PKGS=(
  mingw-w64-x86_64-autotools mingw-w64-x86_64-glew mingw-w64-x86_64-libarchive
  mingw-w64-x86_64-make mingw-w64-x86_64-meson mingw-w64-x86_64-toolchain
  autoconf automake bison flex git libtool nasm p7zip patch unzip zip
)
if [ -z "$ONLY" ] || [[ "$ONLY" == msys2:* ]]; then
  if command -v pacman >/dev/null 2>&1; then
    if [ -z "$ONLY" ]; then
      install_pacman_pkgs "${MSYS2_PKGS[@]}"
    else
      install_pacman_pkgs "${ONLY#msys2:}"
    fi
  fi
fi

want visual_studio_2022 && install_vs2022_buildtools
want cmake             && install_cmake
want python311         && install_python
want strawberry_perl   && install_perl
want rust              && install_rust
want sccache           && install_sccache
want qt                && install_qt

echo "[install-deps] Done."
echo "[install-deps] Reminder: ensure your repo lives under a drive root (e.g. C:\\OpenRV) before bootstrap."
