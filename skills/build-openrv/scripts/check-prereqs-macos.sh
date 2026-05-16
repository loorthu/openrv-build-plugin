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

# Locate sibling helper scripts. BASH_SOURCE may be unset if this script is
# invoked via `bash <name>` rather than execed directly; fall back to $0.
_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Find OpenRV checkout from CWD (same logic as detect-platform.sh) so the TCC
# probe can fall through to the real RV.app when it exists.
_find_openrv_dir() {
  local d="$(pwd)"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -f "$d/rvcmds.sh" ]; then echo "$d"; return; fi
    d="$(dirname "$d")"
  done
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

# Xcode SDK consistency. Even when xcode-select points at full Xcode, xcrun
# without -sdk macosx may resolve to the CLT SDK at
# /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk. shiboken/clang then pick
# up CLT libc++ headers referencing clang intrinsics (e.g. __builtin_ctzg)
# missing from the toolchain bundled with the selected SDK, and PySide6
# binding compiles fail far into the build. run-bootstrap.sh auto-fixes this
# by exporting DEVELOPER_DIR and SDKROOT, but we surface it here so the user
# (or anyone running rvcmds.sh by hand) knows about it.
xcode_dev_path="$(xcode-select -p 2>/dev/null || true)"
if [ -n "$xcode_dev_path" ] && [ "${xcode_dev_path#*Xcode.app/}" != "$xcode_dev_path" ]; then
  default_sdk="$(xcrun --show-sdk-path 2>/dev/null || true)"
  if [ -n "$default_sdk" ] && [ "${default_sdk#*CommandLineTools}" != "$default_sdk" ]; then
    emit "xcode_sdk_consistency" "" "split:$default_sdk" "auto-installable" \
      "SDK split detected: xcrun resolves to CLT SDK while Xcode is selected. run-bootstrap.sh will auto-fix by exporting DEVELOPER_DIR and SDKROOT. To fix manually: export DEVELOPER_DIR=\"\$(xcode-select -p)\"; export SDKROOT=\"\$(xcrun -sdk macosx --show-sdk-path)\""
  else
    emit "xcode_sdk_consistency" "" "ok" "installed" "Xcode SDK consistent ($default_sdk)"
  fi
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

# App Management TCC probe. Uses the realistic-bundle probe (with Info.plist
# + LaunchServices registration) and falls through to a no-op install_name_tool
# against an actual dylib inside _build/stage/app/RV.app if a prior build
# attempt left one there — the latter is the most reliable possible probe.
_openrv_dir_for_probe="$(_find_openrv_dir)"
tcc_state="$(bash "$_self_dir/probe-tcc-macos.sh" "$_openrv_dir_for_probe" 2>/dev/null)"
terminal_app="$(bash "$_self_dir/identify-terminal-macos.sh" 2>/dev/null)"
[ -z "$terminal_app" ] && terminal_app="unknown"

if [ -n "$_openrv_dir_for_probe" ] && [ -d "$_openrv_dir_for_probe/_build/stage/app/RV.app" ]; then
  _probe_what="real RV.app dylib in $_openrv_dir_for_probe"
else
  _probe_what="realistic synthetic bundle"
fi

case "$tcc_state" in
  ok)
    emit "app_management_tcc" "" "ok" "installed" "App Management permission OK (probed against $_probe_what)"
    ;;
  blocked)
    if [ "$terminal_app" != "unknown" ]; then
      hint="App Management TCC is BLOCKING install_name_tool. The build will fail near 99% with 'Operation not permitted' when assembling RV.app. Fix: System Settings → Privacy & Security → App Management → toggle ON $terminal_app. Then FULLY QUIT (Cmd-Q) and relaunch BOTH $terminal_app AND Claude Code — TCC grants do not apply to already-running processes."
    else
      hint="App Management TCC is BLOCKING install_name_tool. The build will fail near 99% with 'Operation not permitted'. Fix: System Settings → Privacy & Security → App Management → toggle ON your terminal app (could not auto-detect which). Then FULLY QUIT and relaunch BOTH your terminal AND Claude Code — TCC grants do not apply to already-running processes."
    fi
    emit "app_management_tcc" "" "blocked" "manual-only" "$hint"
    ;;
  *)
    emit "app_management_tcc" "" "skipped" "manual-only" "Could not probe App Management TCC (no clang or no writable tmp). To be safe, grant App Management permission to ${terminal_app:-your terminal app} in System Settings → Privacy & Security → App Management before building, and FULLY QUIT and relaunch both terminal and Claude Code afterward."
    ;;
esac
