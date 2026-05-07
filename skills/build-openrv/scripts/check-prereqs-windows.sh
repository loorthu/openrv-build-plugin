#!/usr/bin/env bash
# Check OpenRV build prerequisites on Windows. Designed to run inside MSYS2 MinGW64 bash.
# Emits NDJSON (same schema as the macOS/Linux checkers).

set -u

PY_BIN="python3"
command -v python3 >/dev/null 2>&1 || PY_BIN="python"

emit() {
  "$PY_BIN" - "$@" <<'PY'
import json, sys
keys = ["requirement", "min_version", "found_version", "status", "install_hint"]
vals = sys.argv[1:]
obj = {k: (None if v == "__NULL__" else v) for k, v in zip(keys, vals)}
print(json.dumps(obj))
PY
}

ver_winget() { command -v winget >/dev/null 2>&1 && winget --version 2>/dev/null | tr -d 'v\r'; }
ver_choco()  { command -v choco  >/dev/null 2>&1 && choco --version 2>/dev/null | tr -d '\r'; }
ver_cmake()  { command -v cmake  >/dev/null 2>&1 && cmake --version 2>/dev/null | awk 'NR==1 {print $3}'; }
ver_python() { command -v python >/dev/null 2>&1 && python --version 2>&1 | awk '{print $2}'; }
ver_python3(){ command -v python3 >/dev/null 2>&1 && python3 --version 2>&1 | awk '{print $2}'; }
ver_rust()   { command -v rustc  >/dev/null 2>&1 && rustc --version 2>/dev/null | awk '{print $2}'; }
ver_perl()   { [ -x /c/Strawberry/perl/bin/perl ] && /c/Strawberry/perl/bin/perl --version 2>/dev/null | awk '/This is perl/ {print $4}'; }
ver_sccache(){ command -v sccache >/dev/null 2>&1 && sccache --version 2>/dev/null | awk '{print $2}'; }
ver_msys2()  { command -v pacman >/dev/null 2>&1 && pacman --version 2>/dev/null | head -1 | awk '{print $3}'; }

ver_qt() {
  for c in "/c/Qt/6.5.3/msvc2019_64" "${QT_HOME:-/nonexistent}"; do
    if [ -x "$c/bin/qmake6.exe" ] || [ -x "$c/bin/qmake.exe" ]; then
      "$c/bin/qmake6.exe" -query QT_VERSION 2>/dev/null \
        || "$c/bin/qmake.exe" -query QT_VERSION 2>/dev/null
      return
    fi
  done
}

# Visual Studio / MSVC v143 14.40 detection via vswhere
ver_vs2022() {
  local vswhere
  vswhere="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
  [ -x "$vswhere" ] || return
  "$vswhere" -latest -products '*' -version '[17.0,18.0)' -property installationVersion 2>/dev/null
}

has_msvc_14_40() {
  local vs_root
  vs_root="$(/c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio/Installer/vswhere.exe -latest -products '*' -version '[17.0,18.0)' -property installationPath 2>/dev/null | tr -d '\r')"
  [ -n "$vs_root" ] || return 1
  local tools_dir="$vs_root/VC/Tools/MSVC"
  [ -d "$tools_dir" ] || return 1
  ls "$tools_dir" 2>/dev/null | grep -q '^14\.40\.' && return 0 || return 1
}

# Path-length sanity: OpenRV must live under a drive root (e.g. C:\OpenRV)
check_repo_path() {
  local p
  p="$(pwd -W 2>/dev/null || pwd)"
  # If we're inside an OpenRV checkout, check its absolute Windows path length.
  local probe="$p"
  while [ "$probe" != "/" ] && [ "$probe" != "" ]; do
    if [ -f "$probe/rvcmds.sh" ]; then
      local win
      win="$(cd "$probe" && pwd -W 2>/dev/null || cd "$probe" && pwd)"
      echo "$win"
      return
    fi
    probe="$(dirname "$probe")"
  done
}

# --- emit -----------------------------------------------------------------

if   [ -n "$(ver_winget)" ]; then emit "winget" "" "$(ver_winget)" "installed" "winget present"
else emit "winget" "" "__NULL__" "manual-only" "Install App Installer from the Microsoft Store to get winget"
fi

if   [ -n "$(ver_choco)" ]; then emit "choco" "" "$(ver_choco)" "installed" "chocolatey present"
else emit "choco" "" "__NULL__" "auto-installable" "Install chocolatey: see https://chocolatey.org/install"
fi

# MSYS2 (we rely on the user being inside it; check pacman version)
ms_v="$(ver_msys2)"
if [ -n "$ms_v" ]; then
  emit "msys2" "" "$ms_v" "installed" "MSYS2 pacman $ms_v"
else
  emit "msys2" "" "__NULL__" "manual-only" "Install MSYS2 from https://www.msys2.org/ and run from MinGW64 shell"
fi

# MSYS2 packages
MSYS2_PKGS=(
  mingw-w64-x86_64-autotools mingw-w64-x86_64-glew mingw-w64-x86_64-libarchive
  mingw-w64-x86_64-make mingw-w64-x86_64-meson mingw-w64-x86_64-toolchain
  autoconf automake bison flex git libtool nasm p7zip patch unzip zip
)
if command -v pacman >/dev/null 2>&1; then
  for p in "${MSYS2_PKGS[@]}"; do
    if pacman -Qi "$p" >/dev/null 2>&1; then
      emit "msys2:$p" "" "installed" "installed" "$p"
    else
      emit "msys2:$p" "" "__NULL__" "auto-installable" "pacman -Sy --needed --noconfirm $p"
    fi
  done
fi

# Visual Studio 2022 + MSVC v143 14.40
vs_v="$(ver_vs2022)"
if [ -n "$vs_v" ]; then
  if has_msvc_14_40; then
    emit "visual_studio_2022" "17.0" "$vs_v" "installed" "Visual Studio 2022 $vs_v with MSVC v143 14.40"
  else
    emit "visual_studio_2022" "17.0" "$vs_v" "auto-installable" "VS 2022 present but MSVC v143 14.40.x missing; install via winget"
  fi
else
  emit "visual_studio_2022" "17.0" "__NULL__" "auto-installable" "winget install --id Microsoft.VisualStudio.2022.BuildTools --override \"--add Microsoft.VisualStudio.Component.VC.14.40.17.10.x86.x64 --quiet\""
fi

# CMake 3.31+
cm_v="$(ver_cmake)"
if [ -n "$cm_v" ]; then
  ok="$(python -c "from packaging.version import Version; print('y' if Version('$cm_v') >= Version('3.31.0') else 'n')" 2>/dev/null || echo unknown)"
  if [ "$ok" = "y" ]; then
    emit "cmake" "3.31.0" "$cm_v" "installed" "CMake $cm_v"
  else
    emit "cmake" "3.31.0" "$cm_v" "auto-installable" "choco upgrade -y cmake (or winget upgrade Kitware.CMake)"
  fi
else
  emit "cmake" "3.31.0" "__NULL__" "auto-installable" "choco install -y cmake (or winget install Kitware.CMake)"
fi

# Python 3.11.x
py_v="$(ver_python)"
if [ -n "$py_v" ]; then
  emit "python311" "3.11.0" "$py_v" "installed" "Python $py_v"
else
  emit "python311" "3.11.0" "__NULL__" "auto-installable" "winget install Python.Python.3.11"
fi

# Strawberry Perl
pl_v="$(ver_perl)"
if [ -n "$pl_v" ]; then
  emit "strawberry_perl" "" "$pl_v" "installed" "Strawberry Perl $pl_v"
else
  emit "strawberry_perl" "" "__NULL__" "auto-installable" "choco install -y strawberryperl"
fi

# Rust 1.92+
rs_v="$(ver_rust)"
if [ -n "$rs_v" ]; then
  emit "rust" "1.92.0" "$rs_v" "installed" "rustc $rs_v"
else
  emit "rust" "1.92.0" "__NULL__" "auto-installable" "winget install Rustlang.Rustup (then rustup install stable)"
fi

# sccache (preferred over ccache on Windows)
sc_v="$(ver_sccache)"
if [ -n "$sc_v" ]; then
  emit "sccache" "" "$sc_v" "installed" "sccache $sc_v"
else
  emit "sccache" "" "__NULL__" "auto-installable" "cargo install sccache (or winget install Mozilla.sccache)"
fi

# Qt 6.5.3
qt_v="$(ver_qt)"
if [ -n "$qt_v" ]; then
  emit "qt" "6.5.3" "$qt_v" "installed" "Qt $qt_v"
else
  emit "qt" "6.5.3" "__NULL__" "auto-installable" "Headless install via aqtinstall: install-qt.sh"
fi

# Repo path length
repo_path="$(check_repo_path)"
if [ -n "$repo_path" ]; then
  # Heuristic: must be under a drive root with short total path (<= 30 chars before subdirs)
  case "$repo_path" in
    [A-Z]:[/\\]OpenRV*|[A-Z]:[/\\]openrv*|[A-Z]:[/\\][A-Za-z0-9_-]*)
      depth="$(echo "$repo_path" | tr '/\\' '\n' | grep -cv '^$')"
      if [ "$depth" -le 3 ]; then
        emit "repo_path" "" "$repo_path" "installed" "Repo path is short enough"
      else
        emit "repo_path" "" "$repo_path" "manual-only" "Move OpenRV checkout to a drive root (e.g. C:\\OpenRV) — current path will exceed Windows path-length limits during build"
      fi
      ;;
    *)
      emit "repo_path" "" "$repo_path" "manual-only" "Move OpenRV checkout to a drive root (e.g. C:\\OpenRV) to avoid path-length errors"
      ;;
  esac
fi
