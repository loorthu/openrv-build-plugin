#!/usr/bin/env bash
# Idempotently install OpenRV build dependencies on macOS.
#
# Usage:
#   install-deps-macos.sh                # install everything auto-installable; prompt for confirmation per step
#   install-deps-macos.sh --only <name>  # install just one requirement (matches names from check-prereqs-macos.sh)
#   install-deps-macos.sh --elevated     # do not prompt; assume the user has explicitly opted in
#
# Recognized --only names:
#   xcode_clt, brew, brew:<pkg>, python311, cmake, rust, ccache, qt
#
# This script never installs items classified as manual-only by the checker (full Xcode, App Management TCC).

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

# brew bootstrap (works on Apple Silicon and Intel; uses official installer)
install_brew() {
  if command -v brew >/dev/null 2>&1; then return 0; fi
  echo "[install-deps] Bootstrapping Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Activate brew in the current shell on Apple Silicon
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_brew_pkg() {
  local pkg="$1"
  if brew list --formula 2>/dev/null | grep -qx "$pkg"; then
    echo "[install-deps] $pkg already installed"
    return 0
  fi
  echo "[install-deps] brew install $pkg"
  brew install "$pkg"
}

install_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    echo "[install-deps] Xcode CLT already installed"
    return 0
  fi
  echo "[install-deps] Triggering Xcode Command Line Tools install (a system dialog will appear)"
  xcode-select --install || true
  echo "[install-deps] Wait for the GUI install to finish, then re-run."
}

install_rust() {
  if command -v rustc >/dev/null 2>&1; then
    echo "[install-deps] rust already installed"
    return 0
  fi
  echo "[install-deps] Installing Rust via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  # shellcheck disable=SC1091
  [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
}

install_qt() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  echo "[install-deps] Installing Qt 6.5.3 via aqtinstall (no Qt account needed)..."
  bash "$script_dir/install-qt.sh"
}

# --- main ------------------------------------------------------------------

want xcode_clt && install_xcode_clt

if want brew; then
  install_brew
fi

# Core brew packages
for pkg in ninja readline sqlite3 xz zlib autoconf automake libtool yasm nasm meson pkg-config glew clang-format black ccache cmake; do
  want "brew:$pkg" && install_brew_pkg "$pkg"
done
want "brew:tcl-tk@8" && install_brew_pkg "tcl-tk@8"

# Python 3.11 via brew (OpenRV CY2024 hard-pinned)
if want python311; then
  install_brew_pkg "python@3.11"
fi

# CMake — covered above as brew:cmake when ONLY is empty; also accept --only cmake
if [ "$ONLY" = "cmake" ]; then
  install_brew_pkg "cmake"
fi

want rust    && install_rust
want ccache  && install_brew_pkg "ccache"
want qt      && install_qt

echo "[install-deps] Done."
