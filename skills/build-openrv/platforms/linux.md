# Linux playbook

Companion to `SKILL.md`. Read this once you've detected `os == "linux"`.

## Supported

- **Rocky Linux 8 and 9** are the upstream-supported distros for OpenRV CY2024.
- RHEL 8/9 should work identically to Rocky.
- Ubuntu 22.04+ and Debian 12+ are best-effort: the auto-installer maps the most common packages, but the user may need to consult OpenRV's docs if `rvbootstrap` complains about a missing dev header.
- Fedora is unsupported by upstream but usually works once `dnf` package names are mapped.

## Manual-only items

### `sudo` password entry (friendly/auto-open modes only)

The dnf/apt installs need root. If the user picked friendly or auto-open mode, every `sudo` call will prompt for their password unless they've recently authenticated. There's nothing the skill can do about this — just warn them upfront: "I'll be running 5-10 sudo commands. Please stay near the keyboard for the next few minutes."

In autonomous mode (only available when `detect-platform.sh` reports `elevated:true`), the `--elevated` flag is passed to the installer and per-step confirmations are skipped. `sudo` itself still needs a cached credential or passwordless config.

### Repo enablement (Rocky 8/9)

Auto-installable via `dnf config-manager --set-enabled powertools devel` (Rocky 8) or `crb devel` (Rocky 9). If the user's organization restricts repo configuration, this may need IT approval — surface the failure clearly rather than retrying.

## Auto-installable items, pre-flight notes

- **Development Tools group** (`dnf groupinstall "Development Tools"`): pulls gcc, make, autotools, etc. Skipped on apt-based systems (build-essential covers it).
- **gcc-toolset-11** (Rocky 8 only): the system gcc on Rocky 8 is 8.x; OpenRV needs 11. After install, the user must `source /opt/rh/gcc-toolset-11/enable` in the shell where they run `rvbootstrap`. The bootstrap wrapper in OpenRV does this automatically when it detects Rocky 8, but if the user runs CMake by hand later they need to remember.
- **CMake 3.31+**: distro repos ship 3.20-3.26, all too old. The installer builds CMake 3.31.6 from source under `/usr/local`. Takes ~5 minutes. Set `CMAKE_PREFIX` env var to install elsewhere if `/usr/local` is shared.
- **Python 3.11.8 via pyenv**: OpenRV CY2024 hard-pins 3.11. The installer bootstraps pyenv into `~/.pyenv` if missing, then installs 3.11.8. The user's shell rc needs the standard pyenv stanza:

  ```bash
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
  eval "$(pyenv init -)"
  ```

  If the user already has Python 3.11 from another source (system package, conda), `pyenv install` is skipped.
- **Qt 6.5.3**: installed via aqtinstall under `~/Qt/6.5.3/gcc_64`. No Qt account needed.
- **Rust 1.92+**: installed via rustup. If the user already has rustup, this is a no-op; if they have a packaged `rust` from `dnf`/`apt`, the installer leaves it alone (OpenRV's bootstrap will use whichever is on PATH).

## Environment gotchas

- **SELinux** (Rocky/RHEL): enforcing mode is fine for the build itself, but if the user later wants to package OpenRV into an AppImage or RPM, some operations need `permissive` or specific contexts.
- **PulseAudio vs PipeWire**: OpenRV links against PulseAudio's libs (`pulseaudio-libs-devel`). On modern systems with PipeWire, `pipewire-pulse` provides PulseAudio compatibility — having the dev headers installed is what matters.
- **Shared Qt installs**: if the user has a system Qt5 (`qt5-qtbase-devel`), the build still wants Qt 6.5.3 from `~/Qt`. Don't try to replace `qt5-qtbase-devel` — both can coexist.
- **`pkg-config` paths**: if `PKG_CONFIG_PATH` is set in the user's shell, ensure it includes Qt 6.5.3's pkgconfig directory before `rvbootstrap`.

## Build quirks

- First-run cold builds can take 1-3 hours on a typical workstation. ccache cuts subsequent rebuilds dramatically.
- `_build/` lives under the OpenRV checkout. Filesystem must be case-sensitive (default on Linux).
- If `rvbootstrap` fails partway, re-running it usually picks up where it left off thanks to CMake's incremental build. But if a third-party download was interrupted, the half-extracted tree under `_build/_install/` may need manual cleanup. The error message will name the package; `rm -rf _build/_install/<pkg>` and retry.
