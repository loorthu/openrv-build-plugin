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

# Find the OpenRV checkout (if any) in or above CWD and return its absolute
# Windows-form path. MSYS2's `pwd -W` converts /c/foo to C:\foo.
check_repo_path() {
  local probe
  probe="$(pwd -W 2>/dev/null || pwd)"
  while [ "$probe" != "/" ] && [ "$probe" != "" ]; do
    if [ -f "$probe/rvcmds.sh" ]; then
      (cd "$probe" && pwd -W 2>/dev/null || (cd "$probe" && pwd))
      return
    fi
    probe="$(dirname "$probe")"
  done
}

# Probe the Windows registry for the LongPathsEnabled flag. With this enabled
# (DWORD = 1 at HKLM\SYSTEM\CurrentControlSet\Control\FileSystem) the OS lifts
# the legacy 260-byte MAX_PATH limit for tools that opt in via manifest. Most
# OpenRV third-party builds do NOT opt in (they use legacy CRT functions), so
# this is informational only — it does not change our pass/fail threshold,
# but knowing it's off is useful when triaging "file name too long" errors.
probe_long_paths_enabled() {
  local val
  val="$(reg query 'HKLM\SYSTEM\CurrentControlSet\Control\FileSystem' //v LongPathsEnabled 2>/dev/null \
         | grep -oE '0x[0-9a-fA-F]+' | head -1)"
  case "$val" in
    0x1|0x00000001) echo "enabled" ;;
    0x0|0x00000000) echo "disabled" ;;
    *)              echo "unknown" ;;
  esac
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
# Note: avoid python's `packaging` module — it isn't in the stdlib and would
# silently fail-closed if missing, flagging any installed CMake as too old.
ver_ge() {
  [ "$1" = "$2" ] && return 0
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}
cm_v="$(ver_cmake)"
if [ -n "$cm_v" ]; then
  if ver_ge "$cm_v" "3.31.0"; then
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

# Repo path length. Windows has a legacy 260-byte MAX_PATH limit (254 usable
# per OpenRV docs/build_system/config_windows.md). The build tree nests deep:
# _build/RV_DEPS_PYSIDE6/src/RV_DEPS_PYSIDE6-build/<module>/... is easily
# 150-200 chars on its own. To leave headroom, the checkout path itself
# should be <= 40 chars; we hard-fail above 60. OpenRV docs explicitly
# recommend cloning to a drive root (e.g. C:\OpenRV).
repo_path="$(check_repo_path)"
if [ -n "$repo_path" ]; then
  path_len=${#repo_path}
  hint_recovery="Recovery: (1) close any editor/terminal with files open under the current checkout, (2) in a fresh shell run \`mv \"$repo_path\" C:\\\\OpenRV\` (or use Explorer to move it), (3) close this MSYS2 MinGW64 shell and Claude Code, (4) launch a new MSYS2 MinGW64 shell with \`cd C:\\\\OpenRV\` and start Claude Code from there, (5) re-run /openrv-build:build."

  case "$repo_path" in
    [A-Z]:[/\\]*) is_drive_path="yes" ;;
    *)            is_drive_path="no"  ;;
  esac

  if [ "$is_drive_path" = "no" ]; then
    emit "repo_path" "" "$repo_path ($path_len chars)" "manual-only" \
      "Repo is not on a Windows drive (got: $repo_path). The build needs a real Windows path under a drive root like C:\\\\OpenRV. $hint_recovery"
  elif [ "$path_len" -le 40 ]; then
    emit "repo_path" "" "$repo_path ($path_len chars)" "installed" \
      "Repo path length OK ($path_len chars; <= 40 leaves enough headroom for the build tree's deep nesting)."
  elif [ "$path_len" -le 60 ]; then
    emit "repo_path" "" "$repo_path ($path_len chars)" "manual-only" \
      "Repo path is RISKY ($path_len chars; threshold is 40). PySide6 compilation may fail with 'cannot open file: file name too long'. Recommended: move to C:\\\\OpenRV (9 chars). $hint_recovery"
  else
    emit "repo_path" "" "$repo_path ($path_len chars)" "manual-only" \
      "Repo path is TOO LONG ($path_len chars; OpenRV's build tree nests ~150-200 chars deep, total would exceed Windows' 260-byte MAX_PATH limit). The build will fail in PySide6 with 'cannot open file ... too long'. Move to C:\\\\OpenRV. $hint_recovery"
  fi
fi

# LongPathsEnabled (informational). Does NOT raise our pass/fail threshold —
# OpenRV's third-party builds use legacy CRT functions that ignore it — but
# its state helps explain "file name too long" failures during triage.
lpe_state="$(probe_long_paths_enabled)"
case "$lpe_state" in
  enabled)
    emit "long_paths_enabled" "" "enabled" "installed" \
      "Windows LongPathsEnabled is ON. Helps modern tools but does NOT fully fix OpenRV builds — many third-party builds use legacy CRT and ignore this. Keep your repo path short anyway."
    ;;
  disabled)
    emit "long_paths_enabled" "" "disabled" "installed" \
      "Windows LongPathsEnabled is OFF (the default). Strict 260-byte MAX_PATH limit applies. Optional: enable via 'reg add HKLM\\\\SYSTEM\\\\CurrentControlSet\\\\Control\\\\FileSystem /v LongPathsEnabled /t REG_DWORD /d 1 /f' (admin shell). Does not replace the requirement to keep the repo path short."
    ;;
  *)
    emit "long_paths_enabled" "" "unknown" "installed" \
      "Could not probe LongPathsEnabled (reg query failed). Not blocking; informational only."
    ;;
esac
