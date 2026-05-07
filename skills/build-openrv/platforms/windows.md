# Windows playbook

Companion to `SKILL.md`. Read this once you've detected `os == "windows"`.

## Supported

- Windows 10 (22H2) and Windows 11.
- x64 only. ARM64 Windows is not supported by upstream OpenRV CY2024.
- The build runs from an **MSYS2 MinGW64 bash shell** (`C:\msys64\mingw64.exe`). PowerShell, cmd, and WSL are all wrong shells and will produce confusing errors. If `detect-platform.sh` reports `os:"windows"` but the user is in PowerShell/cmd, stop and tell them to relaunch from MinGW64.

## Manual-only items

### Visual Studio 2022 BuildTools — UAC prompt

The winget command to install MSVC v143 14.40 will trigger a UAC prompt. There is no headless workaround unless Claude Code itself was launched from an admin shell with bypass-permissions. Tell the user upfront: "winget will pop a UAC prompt and the installer will run for ~5-15 minutes; please approve when it appears." In auto-open mode the installer's progress window is the standard VS BuildTools UI; let it complete.

If the user is on a managed corporate machine that blocks UAC elevation, they'll need an admin from IT to install VS BuildTools manually. The component they need is **MSVC v143 - VS 2022 C++ x64/x86 build tools (14.40.17.10)** specifically. Other 14.4x versions may work; older 14.3x will not.

### Repo path under a drive root

Windows still has a default 260-character path limit (`MAX_PATH`). OpenRV's third-party builds nest deep enough that anything beyond `C:\OpenRV\<short-subdir>` will fail mid-build with cryptic file-not-found errors.

The prereq checker classifies this as `manual-only` because moving the checkout is a user action. **Walk the user through this:**

1. If the checkout is currently under e.g. `C:\Users\<name>\Documents\GitHub\OpenRV`, tell them: "Windows path-length limits will break this build. Please close any editors/terminals with files open under the current OpenRV checkout, then move it to `C:\OpenRV` (or any short path under a drive root)."
2. After they move, they need to re-launch Claude Code from inside the new path. The session's CWD doesn't follow.
3. Long-path support via the registry (`LongPathsEnabled`) helps for some operations but does not fully fix the problem — many OpenRV third-party builds use legacy CRT functions that ignore it. Don't recommend it as a workaround.

### winget itself

If winget is missing, the user needs to install **App Installer** from the Microsoft Store (the official channel). This needs a Microsoft account; same caveat as the macOS App Store. As a fallback, chocolatey can replace winget for most installs but not all (notably VS BuildTools is more reliable via winget).

## Auto-installable items, pre-flight notes

- **MSYS2** itself: the prereq checker assumes the user is already inside MSYS2. If they aren't, the check fails out — installing MSYS2 is itself manual (download from https://www.msys2.org/, run installer). Surface this clearly: the skill can't bootstrap MSYS2 from a non-MSYS2 shell.
- **MSYS2 packages** (`pacman -Sy`): the toolchain group, autotools, glew, libarchive, meson, plus build utilities (nasm, p7zip, zip, etc). All run inside the MSYS2 environment; no UAC.
- **Strawberry Perl**: needed for OpenSSL builds. Don't substitute ActiveState Perl; its module set differs and OpenRV's third-party scripts assume Strawberry.
- **Python 3.11**: installed via winget (Python.Python.3.11). The Windows store version is **not** suitable — the build invokes Python from MSYS2, which expects a real `python.exe` on `PATH`.
- **Qt 6.5.3**: installed via aqtinstall under `C:\Qt\6.5.3\msvc2019_64`. No Qt account needed. Despite the name, msvc2019_64 is the correct flavor for VS 2022 / MSVC v143.
- **sccache** instead of ccache: ccache doesn't support MSVC well; OpenRV's wrapper looks for sccache on Windows.

## Environment gotchas

- **Long paths during the build**: even with the checkout at `C:\OpenRV`, some third-party builds create deep subdirectories. If a build fails with `cannot open file ... too long`, that's the path-length issue and there is no workaround other than a shorter root.
- **Antivirus**: Windows Defender real-time scanning of `_build/` can multiply build time by 2-4x. If the user has admin, exempting `C:\OpenRV\_build` is worth doing. Ask before recommending — corporate AVs may not allow it.
- **Multiple Python installs**: if the user has Python from the Microsoft Store, ActiveState, conda, and winget all on `PATH`, `which python` from MSYS2 may resolve to the wrong one. Confirm `python --version` reports 3.11.x before bootstrap.
- **Line endings**: ensure `core.autocrlf` is `false` or `input` for the OpenRV checkout. CRLF in shell scripts breaks `rvcmds.sh`. The clone in `pick-openrv-version.sh` does not set this — if the user has a global `core.autocrlf=true`, surface it.

## Build quirks

- First-run cold builds: 1-3 hours on a fast workstation; sccache cuts subsequent rebuilds significantly.
- `rvbootstrap` invokes both MSVC (via vcvars64) and MSYS2 tools (via the MinGW64 shell). The wrapper handles environment switching; the user shouldn't need to source vcvars by hand.
- If the build dies complaining about MSVC version, double-check `vswhere` reports a `14.40.x` toolset under VS 2022. Newer toolsets (14.41+) may produce ABI mismatches with prebuilt third-party Boost.
