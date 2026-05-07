#!/usr/bin/env bash
# Idempotently install OpenRV build dependencies on Linux (Rocky 8/9 primary).
#
# Usage:
#   install-deps-linux.sh                    # everything auto-installable; prompts before sudo
#   install-deps-linux.sh --only <name>      # install one specific item (matches check-prereqs names)
#   install-deps-linux.sh --elevated         # do not prompt; assume user has explicitly opted in

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

distro="unknown"; distro_major=""
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  distro="${ID:-unknown}"
  distro_major="${VERSION_ID%%.*}"
fi

PKG=""
if command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v apt >/dev/null 2>&1; then PKG="apt"
fi

if [ -z "$PKG" ]; then
  echo "[install-deps] No supported package manager (dnf/apt) found." >&2
  exit 1
fi

SUDO="sudo"
[ "$(id -u)" = "0" ] && SUDO=""

# --- helpers ---------------------------------------------------------------

dnf_install() {
  echo "[install-deps] $SUDO dnf install -y $*"
  $SUDO dnf install -y "$@"
}

apt_install() {
  echo "[install-deps] $SUDO apt update && apt install -y $*"
  $SUDO apt update
  $SUDO apt install -y "$@"
}

enable_rocky_repos() {
  case "$distro_major" in
    8)
      $SUDO dnf -y install dnf-plugins-core || true
      $SUDO dnf config-manager --set-enabled powertools devel || true
      ;;
    9)
      $SUDO dnf -y install dnf-plugins-core perl-CPAN || true
      $SUDO dnf config-manager --set-enabled crb devel || true
      ;;
  esac
}

install_devtools_group() {
  $SUDO dnf groupinstall -y "Development Tools"
}

install_gcc_toolset_11() {
  $SUDO dnf install -y gcc-toolset-11-toolchain
}

install_rust() {
  if command -v rustc >/dev/null 2>&1; then return 0; fi
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  # shellcheck disable=SC1091
  [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
}

install_pyenv_python() {
  if [ ! -d "$HOME/.pyenv" ]; then
    curl https://pyenv.run | bash
  fi
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
  if ! pyenv versions --bare 2>/dev/null | grep -qx "3.11.8"; then
    pyenv install -s 3.11.8
  fi
  pyenv global 3.11.8 || true
}

install_cmake_from_source() {
  local ver="3.31.6"
  local prefix="${CMAKE_PREFIX:-/usr/local}"
  local tmp; tmp="$(mktemp -d)"
  pushd "$tmp" >/dev/null
  curl -L -o cmake.tar.gz "https://github.com/Kitware/CMake/releases/download/v${ver}/cmake-${ver}.tar.gz"
  tar xf cmake.tar.gz
  cd "cmake-${ver}"
  ./bootstrap --parallel="$(nproc)" --prefix="$prefix"
  make -j"$(nproc)"
  $SUDO make install
  popd >/dev/null
  rm -rf "$tmp"
}

install_qt() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  bash "$script_dir/install-qt.sh"
}

# --- main ------------------------------------------------------------------

# Repo enablement (Rocky)
if [ "$distro" = "rocky" ] && [ "$PKG" = "dnf" ]; then
  if want rocky_repos; then enable_rocky_repos; fi
fi

# Dev tools group
if [ "$PKG" = "dnf" ] && want devtools_group; then
  install_devtools_group
fi

# Big -devel package list
DEVEL_PKGS_DNF=(
  alsa-lib-devel autoconf automake avahi-compat-libdns_sd-devel bison bzip2-devel
  cmake-gui curl-devel flex gcc gcc-c++ git libXcomposite libXi-devel libaio-devel
  libffi-devel nasm ncurses-devel nss libtool libxkbcommon libXdamage libXrandr
  libXtst libXcursor mesa-libOSMesa mesa-libOSMesa-devel meson openssl-devel patch
  pulseaudio-libs pulseaudio-libs-glib2 ocl-icd ocl-icd-devel opencl-headers
  qt5-qtbase-devel readline-devel sqlite-devel systemd-devel tcl-devel tcsh tk-devel
  yasm zip zlib-devel wget patchelf pcsc-lite libxkbfile perl-IPC-Cmd ccache wget
  epel-release
)

DEVEL_PKGS_APT=(
  build-essential autoconf automake bison flex git libtool nasm yasm
  libssl-dev libreadline-dev libsqlite3-dev libffi-dev libbz2-dev
  libncurses-dev libxkbcommon-dev libxcomposite-dev libxdamage-dev
  libxrandr-dev libxtst-dev libxcursor-dev libosmesa6-dev libxkbfile-dev
  libxi-dev libpulse-dev libavahi-compat-libdnssd-dev qtbase5-dev
  tcl-dev tk-dev meson ninja-build patchelf pkg-config wget ccache
)

if [ "$PKG" = "dnf" ]; then
  if [ -z "$ONLY" ]; then
    dnf_install "${DEVEL_PKGS_DNF[@]}"
  else
    case "$ONLY" in
      dnf:*) dnf_install "${ONLY#dnf:}" ;;
    esac
  fi
elif [ "$PKG" = "apt" ]; then
  if [ -z "$ONLY" ]; then
    apt_install "${DEVEL_PKGS_APT[@]}"
  else
    case "$ONLY" in
      apt:*) apt_install "${ONLY#apt:}" ;;
    esac
  fi
fi

# gcc-toolset-11 (Rocky 8 only)
if [ "$distro" = "rocky" ] && [ "$distro_major" = "8" ] && want gcc_toolset_11; then
  install_gcc_toolset_11
fi

want python311 && install_pyenv_python
want cmake     && install_cmake_from_source
want rust      && install_rust
want ccache    && {
  if [ "$PKG" = "dnf" ]; then dnf_install ccache; else apt_install ccache; fi
}
want qt        && install_qt

echo "[install-deps] Done."
