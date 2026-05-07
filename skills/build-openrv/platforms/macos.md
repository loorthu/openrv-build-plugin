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

This is the one most likely to confuse users. Symptom: build runs for ~30-90 minutes, then near 99% completion `install_name_tool` fails inside an `.app` bundle with a permission error that looks like a linker warning. The actual cause is macOS's App Management TCC restriction.

The prereq checker probes this with `probe_app_management_tcc()`. If it reports `blocked`, the user **must** grant their terminal (Terminal.app, iTerm2, Ghostty, VS Code, whatever spawned this Claude Code session) the App Management permission **before** building. There is no programmatic workaround.

**Walk the user through this:**

1. Identify the terminal app spawning this session. If you can't tell, ask them.
2. In auto-open mode: `scripts/open-installer.sh "x-apple.systempreferences:com.apple.preference.security?Privacy_AppManagement"`.
3. Tell them: "In System Settings → Privacy & Security → App Management, toggle ON the entry for [their terminal app]. If it's not in the list, click the + and add it from /Applications. You may have to enter your password."
4. After they confirm, re-run `check-prereqs-macos.sh` and check the `app_management_tcc` record. It should report `ok`. If it still reports `blocked`, the most common cause is that the user toggled a different app or that the change didn't take effect — they may need to fully quit and relaunch the terminal (and Claude Code) for the new TCC entry to apply. Tell them so.

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
