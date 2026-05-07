# macOS playbook

Companion to `SKILL.md`. Read this once you've detected `os == "macos"`. It covers the items the prereq checker classifies as `manual-only` and the gotchas that cause `rvbootstrap` to fail in confusing ways.

## Supported

- macOS 14 (Sonoma), 15 (Sequoia), 26 (Tahoe) on Apple Silicon and Intel.
- Apple Silicon is primary; Intel works but is less exercised upstream.

## Manual-only items

### Full Xcode (App Store)

The Command Line Tools are auto-installable via `xcode-select --install`. The full Xcode app is **not** — it requires an Apple ID and an App Store login.

**Walk the user through this:**

1. Tell them: "OpenRV needs the full Xcode app, not just the Command Line Tools. The CLT we can trigger automatically; Xcode itself you need to install from the App Store with your Apple ID."
2. In auto-open mode: `scripts/open-installer.sh "macappstore://apps.apple.com/app/xcode/id497799835"`.
3. Once installed, they must launch Xcode once and accept the license — the build will fail otherwise. Tell them to also run `sudo xcodebuild -license accept` (or open Xcode and click Accept).
4. Re-probe: re-run `check-prereqs-macos.sh` and look for the `xcode` record. `found_version` should be non-null.

### App Management TCC grant

This is the one most likely to confuse users. **Failure signature:** the build runs for 1-2 hours, gets ~99% of the way through, then dies with hundreds of identical errors like:

```
install_name_tool: can't open input file: .../RV.app/Contents/MacOS/...dylib for writing (Operation not permitted)
```

The path being modified is in the user's home directory and they own the file — but the OS still denies the write. This is **not** Unix permissions. It is macOS's App Management TCC restriction: any process that tries to modify a file inside any `.app` bundle is gated on whether the app spawning the calling process has been granted App Management permission, regardless of file ownership.

**The plugin handles this in three places:**

1. `scripts/probe-tcc-macos.sh` — produces a realistic synthetic `.app` (with proper `Info.plist` and LaunchServices registration) and tries `install_name_tool` on a dylib inside it. If a previous build attempt produced `_build/stage/app/RV.app`, the probe falls through to a no-op `install_name_tool -id` against an actual dylib in that bundle, which is the most reliable possible probe. The earlier bare-directory probe gave false-passes because TCC didn't classify it as an app.
2. `scripts/identify-terminal-macos.sh` — walks up the process tree to find the outermost `.app` ancestor, so the install_hint can name the specific terminal (`Ghostty.app`, `Terminal.app`, `Visual Studio Code.app`) instead of vague "your terminal".
3. `scripts/run-bootstrap.sh` — runs the probe as a pre-flight gate before sourcing `rvcmds.sh`. If TCC is blocking, the wrapper exits with code 3 and a clear actionable message instead of starting a doomed multi-hour build.

**Walking the user through the fix:**

1. The probe will tell you which app to grant permission to. It's named in the install_hint, e.g. `Toggle ON: Ghostty.app`.
2. In auto-open mode: `scripts/open-installer.sh "x-apple.systempreferences:com.apple.preference.security?Privacy_AppManagement"` opens the right pane.
3. Tell the user: "In System Settings → Privacy & Security → App Management, toggle ON the entry for [the named app]. If it's not in the list, click the + and add it from /Applications. You may have to enter your Mac password."
4. **Critical relaunch step:** TCC grants do not apply to already-running processes. The user MUST fully quit (Cmd-Q) and relaunch BOTH the terminal AND Claude Code. Just closing the window is not enough. This is the second-most-common reason the fix appears not to work.
5. After relaunch, re-run `check-prereqs-macos.sh` to verify `app_management_tcc` reports `ok`. If still `blocked`, ask whether they actually quit the apps (Cmd-Tab → see if either is still in the dock with a dot under it).

## Auto-installable items, pre-flight notes

- **Homebrew**: bootstrapper is the official one-liner. On Apple Silicon, brew lives at `/opt/homebrew`; on Intel, `/usr/local`. The install script handles `eval $(brew shellenv)` for the current process, but later sessions need the user's shell rc to source it.
- **python@3.11**: OpenRV CY2024 hard-pins 3.11. Don't substitute 3.12 or 3.13.
- **tcl-tk@8**: special name (versioned); not interchangeable with current `tcl-tk`.
- **Qt 6.5.3**: installed via aqtinstall under `~/Qt/6.5.3/macos`. No Qt account needed. Modules pulled: qtwebengine, qtwebsockets, qtmultimedia, qtdeclarative, qtwebchannel, qtpositioning, qtimageformats, qt5compat. If the user already has Qt installed elsewhere, set `QT_HOME` to that path and skip this step.

## Environment gotchas

These are the things that break `rvbootstrap` on otherwise-clean macOS setups. The `run-bootstrap.sh` wrapper handles the SDK and deployment-target items automatically; the others are surfaced for users running `source rvcmds.sh` by hand.

- **Xcode/CLT SDK split**: even when `xcode-select -p` correctly points at `/Applications/Xcode.app/Contents/Developer`, `xcrun --show-sdk-path` (without `-sdk macosx`) can resolve to `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`. shiboken/clang then pick up CLT libc++ headers that reference clang intrinsics (`__builtin_ctzg`, `__builtin_clzg`, etc.) missing from the toolchain bundled with the selected SDK, and **every PySide6 binding compile fails**. The build dies tens of minutes in with hundreds of identical "no member named '__builtin_ctzg'" errors. `run-bootstrap.sh` exports `DEVELOPER_DIR` and `SDKROOT` to Xcode's paths automatically; the prereq checker reports this under `xcode_sdk_consistency`. To fix manually: `export DEVELOPER_DIR="$(xcode-select -p)"; export SDKROOT="$(xcrun -sdk macosx --show-sdk-path)"`.
- **`MACOSX_DEPLOYMENT_TARGET`**: leave unset. OpenRV's CMake decides. Overriding it produces "linked against newer SDK" warnings or outright link failures. `run-bootstrap.sh` unsets it.
- **`SSL_CERT_FILE`**: if set system-wide for proxy/SSL inspection, *some* OpenRV third-party builds (notably anything using Python's `ssl` module via `urllib`) will pick it up correctly, but Python builds from source can fail if the file path becomes unreadable mid-build. If you see SSL errors during the third-party fetch phase, double-check the CA bundle path is still valid. Prefer `REQUESTS_CA_BUNDLE` and `CURL_CA_BUNDLE` over `SSL_CERT_FILE` when possible.
- **Netskope / corporate proxies**: confirm `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`, or `SSL_CERT_FILE` is exported and points to the corporate CA bundle before launching Claude Code.

## Build quirks

- First-run cold builds can take 2-4 hours on M-series; ccache cuts subsequent rebuilds to ~30 minutes.
- `rvbootstrap` writes to `_build/`. To start over from scratch, `rm -rf _build` is safe (slow).
- If the build fails near the very end with `install_name_tool` errors and TCC was already granted, check that the user did not move/rename their terminal app between the TCC grant and the build — TCC grants are tied to the app's bundle identifier and code signature.
