#!/usr/bin/env bash
# Check OpenRV build prerequisites on macOS.
# Emits one JSON object per line on stdout (NDJSON), one per requirement.
# Schema:
#   {
#     "requirement":   "cmake" | "qt" | ...,
#     "min_version":   "3.31.0" | "" if version-less,
#     "found_version": "<detected version>" | null if not installed,
#     "status":        "installed" | "auto-installable" | "manual-only",
#     "install_hint":  human-friendly one-line description of how to install
#   }
#
# Categorization rules (per the plan):
#   - Anything brew/pip/aqtinstall/rustup can install -> auto-installable
#   - Xcode (full IDE), App Management TCC grant -> manual-only
#   - Xcode CLT triggers a GUI prompt but no Apple ID, treat as auto-installable

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

# --- detect helpers --------------------------------------------------------

ver_cmake()    { command -v cmake    >/dev/null 2>&1 && cmake --version 2>/dev/null    | awk 'NR==1 {print $3}'; }
ver_python()   { command -v python3.11 >/dev/null 2>&1 && python3.11 --version 2>&1 | awk '{print $2}'; }
ver_ninja()    { command -v ninja    >/dev/null 2>&1 && ninja --version 2>/dev/null; }
ver_brew()     { command -v brew     >/dev/null 2>&1 && brew --version 2>/dev/null      | awk 'NR==1 {print $2}'; }
ver_rust()     { command -v rustc    >/dev/null 2>&1 && rustc --version 2>/dev/null     | awk '{print $2}'; }
ver_ccache()   { command -v ccache   >/dev/null 2>&1 && ccache --version 2>/dev/null    | awk 'NR==1 {print $3}'; }
ver_meson()    { command -v meson    >/dev/null 2>&1 && meson --version 2>/dev/null; }
ver_nasm()     { command -v nasm     >/dev/null 2>&1 && nasm -v 2>/dev/null              | awk '{print $3}'; }
ver_yasm()     { command -v yasm     >/dev/null 2>&1 && yasm --version 2>/dev/null       | awk 'NR==1 {print $2}'; }
ver_autoconf() { command -v autoconf >/dev/null 2>&1 && autoconf --version 2>/dev/null   | awk 'NR==1 {print $NF}'; }
ver_pkgcfg()   { command -v pkg-config >/dev/null 2>&1 && pkg-config --version 2>/dev/null; }
ver_libtool()  { command -v libtool >/dev/null 2>&1 && libtool --version 2>/dev/null      | awk 'NR==1 {print $NF}'; }

ver_xcode_clt() {
  # Returns the xcode-select active-developer-dir path if present, blank otherwise.
  if xcode-select -p >/dev/null 2>&1; then
    xcode-select -p 2>/dev/null
  fi
}

ver_xcode() {
  # Return version of the full Xcode app (not just CLT) if installed.
  local p
  p="$(xcode-select -p 2>/dev/null || true)"
  if [ -n "$p" ] && [ -x "${p%/Contents/Developer}/Contents/MacOS/Xcode" ]; then
    /usr/bin/xcodebuild -version 2>/dev/null | awk 'NR==1 {print $2}'
  fi
}

ver_qt() {
  # Look in canonical aqtinstall and Qt-installer locations
  local candidates=(
    "$HOME/Qt/6.5.3/macos"
    "$HOME/Qt/6.5.3/clang_64"
    "${QT_HOME:-/nonexistent}"
  )
  for c in "${candidates[@]}"; do
    if [ -x "$c/bin/qmake6" ] || [ -x "$c/bin/qmake" ]; then
      "$c/bin/qmake6" -query QT_VERSION 2>/dev/null \
        || "$c/bin/qmake" -query QT_VERSION 2>/dev/null
      return
    fi
  done
}

# Probe whether `install_name_tool` can edit a Mach-O without TCC blocking us.
# We don't actually need TCC for plain Mach-O edits; but for editing dylibs
# inside a *.app bundle the App Management permission is required. We probe by
# creating a throwaway dylib in a fake .app and trying to set its rpath. If
# this fails with a TCC denial, return "blocked".
probe_app_management_tcc() {
  local tmp dylib_src dylib appdir
  tmp="$(mktemp -d 2>/dev/null)" || { echo "unknown"; return; }
  appdir="$tmp/probe.app/Contents/MacOS"
  mkdir -p "$appdir"
  dylib_src="$tmp/probe.c"
  dylib="$appdir/libprobe.dylib"
  printf 'int probe(){return 0;}\n' > "$dylib_src"
  # Compile a minimal dylib (requires CLT). If CLT is absent, we can't probe.
  if ! command -v clang >/dev/null 2>&1; then
    echo "skipped"
    rm -rf "$tmp"
    return
  fi
  if ! clang -dynamiclib -o "$dylib" "$dylib_src" 2>/dev/null; then
    echo "skipped"
    rm -rf "$tmp"
    return
  fi
  # Attempt the kind of operation OpenRV does during build
  if install_name_tool -id "@rpath/libprobe.dylib" "$dylib" 2>/dev/null; then
    echo "ok"
  else
    echo "blocked"
  fi
  rm -rf "$tmp"
}

# --- emit one record per requirement --------------------------------------

# Xcode CLT
clt_path="$(ver_xcode_clt)"
if [ -n "$clt_path" ]; then
  emit "xcode_clt" "" "$clt_path" "installed" "Xcode Command Line Tools detected at $clt_path"
else
  emit "xcode_clt" "" "__NULL__" "auto-installable" "Run xcode-select --install (GUI prompt, no Apple ID needed)"
fi

# Full Xcode (recommended for OpenRV). Optional but encouraged.
xc_ver="$(ver_xcode)"
if [ -n "$xc_ver" ]; then
  emit "xcode" "16.4" "$xc_ver" "installed" "Xcode $xc_ver"
else
  emit "xcode" "16.4" "__NULL__" "manual-only" "Install Xcode from the App Store (requires Apple ID)"
fi

# Homebrew
brew_v="$(ver_brew)"
if [ -n "$brew_v" ]; then
  emit "brew" "" "$brew_v" "installed" "Homebrew $brew_v"
else
  emit "brew" "" "__NULL__" "auto-installable" "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
fi

# Brew packages OpenRV needs
for pkg in ninja readline sqlite3 xz zlib autoconf automake libtool yasm nasm meson pkg-config glew clang-format black; do
  if brew list --formula 2>/dev/null | grep -qx "$pkg"; then
    emit "brew:$pkg" "" "installed" "installed" "brew package $pkg"
  else
    emit "brew:$pkg" "" "__NULL__" "auto-installable" "brew install $pkg"
  fi
done

# tcl-tk@8 (special name)
if brew list --formula 2>/dev/null | grep -qx "tcl-tk@8"; then
  emit "brew:tcl-tk@8" "" "installed" "installed" "brew package tcl-tk@8"
else
  emit "brew:tcl-tk@8" "" "__NULL__" "auto-installable" "brew install tcl-tk@8"
fi

# python@3.11 via brew (required by OpenRV CY2024)
py_v="$(ver_python)"
if [ -n "$py_v" ]; then
  emit "python311" "3.11.0" "$py_v" "installed" "Python $py_v"
else
  emit "python311" "3.11.0" "__NULL__" "auto-installable" "brew install python@3.11"
fi

# CMake (must be 3.31+; brew's may be too old, but we still try brew first)
cm_v="$(ver_cmake)"
if [ -n "$cm_v" ]; then
  # Compare to 3.31.0
  ok="$(python3 -c "from packaging.version import Version; print('y' if Version('$cm_v') >= Version('3.31.0') else 'n')" 2>/dev/null || echo 'unknown')"
  if [ "$ok" = "y" ]; then
    emit "cmake" "3.31.0" "$cm_v" "installed" "CMake $cm_v"
  else
    emit "cmake" "3.31.0" "$cm_v" "auto-installable" "brew install cmake (or upgrade: brew upgrade cmake)"
  fi
else
  emit "cmake" "3.31.0" "__NULL__" "auto-installable" "brew install cmake"
fi

# Rust (1.92+ per docs; brew or rustup)
rs_v="$(ver_rust)"
if [ -n "$rs_v" ]; then
  emit "rust" "1.92.0" "$rs_v" "installed" "rustc $rs_v"
else
  emit "rust" "1.92.0" "__NULL__" "auto-installable" "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
fi

# ccache (optional but strongly recommended; 50-80% rebuild speedup)
cc_v="$(ver_ccache)"
if [ -n "$cc_v" ]; then
  emit "ccache" "" "$cc_v" "installed" "ccache $cc_v"
else
  emit "ccache" "" "__NULL__" "auto-installable" "brew install ccache"
fi

# Qt 6.5.3
qt_v="$(ver_qt)"
if [ -n "$qt_v" ]; then
  emit "qt" "6.5.3" "$qt_v" "installed" "Qt $qt_v"
else
  emit "qt" "6.5.3" "__NULL__" "auto-installable" "Headless install via aqtinstall: install-qt.sh"
fi

# App Management TCC probe
tcc_state="$(probe_app_management_tcc)"
case "$tcc_state" in
  ok)
    emit "app_management_tcc" "" "ok" "installed" "App Management permission OK"
    ;;
  blocked)
    emit "app_management_tcc" "" "blocked" "manual-only" "Grant App Management permission to your terminal in System Settings -> Privacy & Security -> App Management"
    ;;
  *)
    emit "app_management_tcc" "" "skipped" "manual-only" "Could not probe App Management TCC (no clang); grant permission to your terminal under System Settings -> Privacy & Security -> App Management before building"
    ;;
esac
