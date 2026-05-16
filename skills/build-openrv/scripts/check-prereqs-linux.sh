#!/usr/bin/env bash
# Check OpenRV build prerequisites on Linux (Rocky 8/9 primary; best-effort on RHEL/Fedora/Ubuntu).
# Emits NDJSON, one JSON object per requirement (same schema as check-prereqs-macos.sh).

set -u

emit() {
  python3 - "$@" <<'PY'
import json, sys
keys = ["requirement", "min_version", "found_version", "status", "install_hint"]
vals = sys.argv[1:]
obj = {k: (None if v == "__NULL__" else v) for k, v in zip(keys, vals)}
print(json.dumps(obj))
PY
}

distro="unknown"
distro_major=""
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

# --- detect helpers --------------------------------------------------------

ver_cmake()  { command -v cmake  >/dev/null 2>&1 && cmake --version 2>/dev/null  | awk 'NR==1 {print $3}'; }
ver_ninja()  { command -v ninja  >/dev/null 2>&1 && ninja --version 2>/dev/null; }
ver_rust()   { command -v rustc  >/dev/null 2>&1 && rustc --version 2>/dev/null  | awk '{print $2}'; }
ver_ccache() { command -v ccache >/dev/null 2>&1 && ccache --version 2>/dev/null | awk 'NR==1 {print $3}'; }
ver_meson()  { command -v meson  >/dev/null 2>&1 && meson --version 2>/dev/null; }
ver_gcc()    { command -v gcc    >/dev/null 2>&1 && gcc --version 2>/dev/null    | awk 'NR==1 {print $NF}'; }

ver_python311() {
  if command -v python3.11 >/dev/null 2>&1; then
    python3.11 --version 2>&1 | awk '{print $2}'
    return
  fi
  if [ -x "$HOME/.pyenv/versions/3.11.8/bin/python3.11" ]; then
    "$HOME/.pyenv/versions/3.11.8/bin/python3.11" --version 2>&1 | awk '{print $2}'
    return
  fi
}

ver_pyenv() {
  if command -v pyenv >/dev/null 2>&1; then
    pyenv --version 2>/dev/null | awk '{print $2}'
  elif [ -d "$HOME/.pyenv" ]; then
    "$HOME/.pyenv/bin/pyenv" --version 2>/dev/null | awk '{print $2}'
  fi
}

ver_qt() {
  for c in "$HOME/Qt/6.5.3/gcc_64" "${QT_HOME:-/nonexistent}"; do
    if [ -x "$c/bin/qmake6" ] || [ -x "$c/bin/qmake" ]; then
      "$c/bin/qmake6" -query QT_VERSION 2>/dev/null \
        || "$c/bin/qmake" -query QT_VERSION 2>/dev/null
      return
    fi
  done
}

dnf_have_group_devtools() {
  command -v dnf >/dev/null 2>&1 || return 1
  dnf grouplist installed 2>/dev/null | grep -qi 'Development Tools'
}

dnf_pkg_installed() {
  rpm -q "$1" >/dev/null 2>&1
}

apt_pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

# --- emit one record per requirement --------------------------------------

# Distro tag (informational)
emit "distro" "" "${distro}${distro_major:+:$distro_major}" "installed" "Detected distro: $distro $distro_major"

# Package manager presence
if [ -n "$PKG" ]; then
  emit "pkg_manager" "" "$PKG" "installed" "Using $PKG"
else
  emit "pkg_manager" "" "__NULL__" "manual-only" "No supported package manager (dnf/apt) found"
fi

# Repo enablement (Rocky-specific). On Ubuntu/Debian skip.
if [ "$distro" = "rocky" ] && [ "$PKG" = "dnf" ]; then
  case "$distro_major" in
    8)
      if dnf repolist --enabled 2>/dev/null | grep -q '^powertools'; then
        emit "rocky_repos" "" "enabled" "installed" "powertools+devel repos enabled"
      else
        emit "rocky_repos" "" "disabled" "auto-installable" "sudo dnf config-manager --set-enabled powertools devel"
      fi
      ;;
    9)
      if dnf repolist --enabled 2>/dev/null | grep -q '^crb'; then
        emit "rocky_repos" "" "enabled" "installed" "crb+devel repos enabled"
      else
        emit "rocky_repos" "" "disabled" "auto-installable" "sudo dnf config-manager --set-enabled crb devel"
      fi
      ;;
  esac
fi

# Development Tools group (dnf)
if [ "$PKG" = "dnf" ]; then
  if dnf_have_group_devtools; then
    emit "devtools_group" "" "installed" "installed" "Development Tools group present"
  else
    emit "devtools_group" "" "__NULL__" "auto-installable" "sudo dnf groupinstall -y \"Development Tools\""
  fi
fi

# Core devel packages (dnf names; mapped from docs/build_system/config_linux_rocky89.md)
DEVEL_PKGS=(
  alsa-lib-devel autoconf automake avahi-compat-libdns_sd-devel bison bzip2-devel
  cmake-gui libcurl-devel flex gcc gcc-c++ git libXcomposite libXi-devel libaio-devel
  libffi-devel nasm ncurses-devel nss libtool libxkbcommon libxkbcommon-devel
  libXdamage libXrandr libXtst libXcursor mesa-libGLU-devel mesa-libOSMesa
  mesa-libOSMesa-devel meson openssl-devel patch pulseaudio-libs
  pulseaudio-libs-glib2 ocl-icd ocl-icd-devel opencl-headers
  qt5-qtbase-devel readline-devel sqlite-devel systemd-devel tcl-devel tcsh tk-devel
  yasm zip zlib-devel wget patchelf pcsc-lite libxkbfile perl-IPC-Cmd
)

if [ "$PKG" = "dnf" ]; then
  for p in "${DEVEL_PKGS[@]}"; do
    if dnf_pkg_installed "$p"; then
      emit "dnf:$p" "" "installed" "installed" "$p"
    else
      emit "dnf:$p" "" "__NULL__" "auto-installable" "sudo dnf install -y $p"
    fi
  done
elif [ "$PKG" = "apt" ]; then
  # Best-effort apt mapping (Ubuntu/Debian users will need to consult OpenRV docs;
  # we report what we can and leave the rest to the user).
  for p in build-essential autoconf automake bison flex git libtool nasm yasm \
           libssl-dev libreadline-dev libsqlite3-dev libffi-dev libbz2-dev \
           libncurses-dev libxkbcommon-dev libxcomposite-dev libxdamage-dev \
           libxrandr-dev libxtst-dev libxcursor-dev libosmesa6-dev libxkbfile-dev \
           libxi-dev libpulse-dev libavahi-compat-libdnssd-dev libglu1-mesa-dev \
           qtbase5-dev tcl-dev tk-dev meson ninja-build patchelf pkg-config wget; do
    if apt_pkg_installed "$p"; then
      emit "apt:$p" "" "installed" "installed" "$p"
    else
      emit "apt:$p" "" "__NULL__" "auto-installable" "sudo apt install -y $p"
    fi
  done
fi

# gcc-toolset-11 on Rocky 8 (required because system gcc is 8.x)
if [ "$distro" = "rocky" ] && [ "$distro_major" = "8" ]; then
  if rpm -q gcc-toolset-11-toolchain >/dev/null 2>&1 || rpm -q gcc-toolset-11 >/dev/null 2>&1; then
    emit "gcc_toolset_11" "" "installed" "installed" "gcc-toolset-11 present (remember to: source /opt/rh/gcc-toolset-11/enable)"
  else
    emit "gcc_toolset_11" "" "__NULL__" "auto-installable" "sudo dnf install -y gcc-toolset-11-toolchain"
  fi
fi

# pyenv (used to install pinned Python 3.11.8)
py_v="$(ver_python311)"
if [ -n "$py_v" ]; then
  emit "python311" "3.11.8" "$py_v" "installed" "Python $py_v"
else
  pe_v="$(ver_pyenv)"
  if [ -n "$pe_v" ]; then
    emit "python311" "3.11.8" "__NULL__" "auto-installable" "pyenv install 3.11.8"
  else
    emit "python311" "3.11.8" "__NULL__" "auto-installable" "Install pyenv (curl https://pyenv.run | bash) then pyenv install 3.11.8"
  fi
fi

# CMake 3.31+
# Note: avoid python's `packaging` module — it isn't in the stdlib and isn't
# present on a fresh Rocky/RHEL system, which would silently fail-closed and
# flag any installed CMake as too old. `sort -V` is in coreutils everywhere.
ver_ge() {
  [ "$1" = "$2" ] && return 0
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}
cm_v="$(ver_cmake)"
if [ -n "$cm_v" ]; then
  if ver_ge "$cm_v" "3.31.0"; then
    emit "cmake" "3.31.0" "$cm_v" "installed" "CMake $cm_v"
  else
    emit "cmake" "3.31.0" "$cm_v" "auto-installable" "Build CMake 3.31 from source (distro repos are too old)"
  fi
else
  emit "cmake" "3.31.0" "__NULL__" "auto-installable" "Build CMake 3.31 from source (distro repos are too old)"
fi

# Rust 1.92+
rs_v="$(ver_rust)"
if [ -n "$rs_v" ]; then
  emit "rust" "1.92.0" "$rs_v" "installed" "rustc $rs_v"
else
  emit "rust" "1.92.0" "__NULL__" "auto-installable" "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
fi

# ccache
cc_v="$(ver_ccache)"
if [ -n "$cc_v" ]; then
  emit "ccache" "" "$cc_v" "installed" "ccache $cc_v"
else
  emit "ccache" "" "__NULL__" "auto-installable" "sudo $PKG install -y ccache"
fi

# Qt 6.5.3
qt_v="$(ver_qt)"
if [ -n "$qt_v" ]; then
  emit "qt" "6.5.3" "$qt_v" "installed" "Qt $qt_v"
else
  emit "qt" "6.5.3" "__NULL__" "auto-installable" "Headless install via aqtinstall: install-qt.sh"
fi
