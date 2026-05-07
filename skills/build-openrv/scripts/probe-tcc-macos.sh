#!/usr/bin/env bash
# Probe whether macOS App Management TCC will block install_name_tool from
# modifying files inside .app bundles.
#
# OpenRV's build assembles RV.app and runs install_name_tool against the
# dylibs inside it to rewrite their LC_ID_DYLIB / LC_RPATH headers. macOS
# gates that operation behind App Management TCC: even if the user owns the
# files (the bundle is in their home directory), the system denies the write
# unless the parent app of the calling process has been granted App
# Management permission in System Settings.
#
# This probe tries the same operation in a controlled setting and reports
# whether it succeeds. It uses two strategies, in order of reliability:
#
#   1. If <openrv_dir>/_build/stage/app/RV.app exists and contains a dylib,
#      try a no-op install_name_tool against THAT dylib. This is the most
#      reliable possible probe because it exercises the exact path the
#      build will hit.
#
#   2. Otherwise, build a realistic synthetic .app under $TMPDIR with a
#      proper Info.plist and register it with LaunchServices. The naked
#      directory tree the previous version of this probe used did not
#      trigger App Management enforcement, so a bare-tree probe could
#      report "ok" while the real build still failed.
#
# Output (single line on stdout):
#   ok       - install_name_tool succeeded; TCC is not blocking
#   blocked  - install_name_tool failed with EPERM; TCC is blocking
#   skipped  - could not run probe (no clang, no writable tmp, etc.)
#
# Exit code matches: 0 ok, 1 blocked, 2 skipped.

set -u

openrv_dir="${1:-}"

[ "$(uname -s)" = "Darwin" ] || { echo "skipped"; exit 2; }

# --- option 1: probe real RV.app if it exists ------------------------------

if [ -n "$openrv_dir" ] && [ -d "$openrv_dir/_build/stage/app/RV.app/Contents/MacOS" ]; then
  real_dylib="$(find "$openrv_dir/_build/stage/app/RV.app/Contents/MacOS" \
                 -maxdepth 4 -name '*.dylib' -type f 2>/dev/null | head -1)"
  if [ -n "$real_dylib" ] && [ -w "$real_dylib" ]; then
    cur_id="$(otool -D "$real_dylib" 2>/dev/null | tail -1)"
    if [ -n "$cur_id" ] && [ "$cur_id" != "$real_dylib:" ]; then
      # No-op rewrite: set the id back to its current value. install_name_tool
      # still rewrites the Mach-O so TCC enforcement still triggers.
      if install_name_tool -id "$cur_id" "$real_dylib" 2>/dev/null; then
        echo "ok"; exit 0
      else
        echo "blocked"; exit 1
      fi
    fi
  fi
fi

# --- option 2: synthetic realistic bundle ----------------------------------

if ! command -v clang >/dev/null 2>&1; then
  echo "skipped"; exit 2
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/openrv-tccprobe.XXXXXX" 2>/dev/null)" \
  || { echo "skipped"; exit 2; }
trap 'rm -rf "$tmp" 2>/dev/null' EXIT

contents="$tmp/Probe.app/Contents"
macos="$contents/MacOS"
plist="$contents/Info.plist"
mkdir -p "$macos" || { echo "skipped"; exit 2; }

bundle_id="com.openrv.tccprobe.$$.$(date +%s 2>/dev/null || echo 0)"

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Probe</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleName</key><string>Probe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
EOF

src="$tmp/probe.c"
dylib="$macos/libprobe.dylib"
printf 'int probe(){return 0;}\n' > "$src"

if ! clang -dynamiclib -o "$dylib" "$src" 2>/dev/null; then
  echo "skipped"; exit 2
fi

# Register with LaunchServices so TCC classifies this as an app.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$tmp/Probe.app" 2>/dev/null || true
fi

if install_name_tool -id "@rpath/libprobe.dylib" "$dylib" 2>/dev/null; then
  result="ok"
else
  result="blocked"
fi

# Best-effort unregister so we don't leave the bundle in LS db.
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -u "$tmp/Probe.app" 2>/dev/null || true
fi

echo "$result"
case "$result" in
  ok)      exit 0 ;;
  blocked) exit 1 ;;
esac
