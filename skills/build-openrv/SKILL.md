---
name: build-openrv
description: Guide a user through compiling OpenRV from source on macOS, Rocky Linux 8/9, or Windows 10/11. Detects platform, runs prereq checks, installs everything that can be installed automatically (brew, dnf/apt, winget/choco, pacman, pip, rustup, aqtinstall), and walks the user through anything that genuinely requires a human (Apple ID for Xcode, MSVC component picker, macOS App Management TCC grant). Trigger on requests like "build OpenRV", "compile OpenRV", "set up OpenRV from source", or when the user is in a directory containing rvcmds.sh and asks for help getting it to build.
---

# Build OpenRV from source

You are guiding a user through compiling OpenRV. This is a long process (~30-90 minutes wall clock once dependencies are in place; first-time setup can be several hours on a clean machine). Most users invoking this skill are not C++ build experts. Be patient, explain what each step does in plain language, and never silently skip a check.

## Operating principles

1. **One step at a time.** Detect → report → confirm → act → verify. Do not chain installs. If something fails, stop and surface the actual error before retrying.
2. **Idempotent.** Every script in `scripts/` can be re-run safely. If the user re-invokes the skill mid-flow, re-run the relevant check rather than assuming prior state.
3. **Honor the automation level.** The user picks one at the start (see §Modes). Do not silently escalate.
4. **Don't invent versions, package names, or flags.** All hard data lives in `scripts/` and `platforms/<os>.md`. If a script reports something you don't recognize, ask the user rather than guessing.
5. **Surface the OpenRV build wrapper, don't replace it.** The actual build is `source rvcmds.sh && rvbootstrap`. The skill's job is environment, dependencies, and pacing — not reimplementing the build.

## Directory layout

- `scripts/detect-platform.sh` — emits one-line JSON about OS, arch, package manager, elevated state, CA bundle, and whether the CWD is already inside an OpenRV checkout.
- `scripts/pick-openrv-version.sh list` — lists recent upstream tags + `main`.
- `scripts/pick-openrv-version.sh prepare <ref> [<dir>]` — clones or checks out the chosen ref. Prints final absolute path on stdout.
- `scripts/check-prereqs-{macos,linux,windows}.sh` — emit NDJSON, one record per requirement: `{requirement, min_version, found_version, status, install_hint}`. `status` is `installed`, `auto-installable`, or `manual-only`.
- `scripts/install-deps-{macos,linux,windows}.sh` — install everything auto-installable. Accepts `--only <name>` to install one item, or `--elevated` to skip per-step confirmations (only pass this when the user is in fully-autonomous mode).
- `scripts/install-qt.sh` — headless Qt 6.5.3 install via aqtinstall. Prints resolved `QT_HOME` on stdout.
- `scripts/open-installer.sh <url-or-path>` — opens a URL or file in the default handler (auto-open mode only).
- `platforms/macos.md`, `platforms/linux.md`, `platforms/windows.md` — per-platform manual-step playbooks. Read the relevant one once you know the OS.

## Modes

Ask the user once, near the start. Default to **friendly walkthrough** if they don't pick.

- **friendly** (default) — Pause before every install. Show what's about to happen, wait for "go". For manual steps, explain what to click and wait for "done".
- **auto-open** — Same as friendly, but call `scripts/open-installer.sh` to open App Store / installer pages / System Settings panes for the user.
- **autonomous** — Only offer this if `detect-platform.sh` reports `"elevated":"true"`. Pass `--elevated` to install scripts so they don't prompt. Still show a one-screen warning before the first sudo/admin command listing what will run, and require an explicit "yes, proceed" before the first install. After that, run without per-step confirmation but report each install as it happens.

## The flow

### 1. Pick a version

Run `scripts/pick-openrv-version.sh list`. Show the user:
- Current checkout (if any) and its ref.
- Up to 10 recent release tags.
- The `main` branch as an option.

Ask which to build. If the CWD is already an OpenRV checkout at the requested ref, skip prepare. Otherwise run `scripts/pick-openrv-version.sh prepare <ref> [<target_dir>]` and `cd` into the printed path for the rest of the session.

If they want a target directory other than CWD/`OpenRV`, ask and pass it as the third arg.

### 2. Detect the platform

Run `scripts/detect-platform.sh`. Parse the JSON. Tell the user in one sentence what you detected: OS, distro, arch, package manager, whether the shell can sudo without a prompt, and whether a CA bundle is set.

Special handling:
- `os == "windows"` and you're not in MSYS2/MinGW64 — stop and tell the user to relaunch Claude Code from the **MSYS2 MinGW64 shell** (`C:\msys64\mingw64.exe`). Everything else assumes that environment.
- `ca_bundle` non-empty — note it; pass through naturally (env vars propagate to subprocesses; no extra work needed).
- `elevated == "false"` and the user picked autonomous — downgrade to friendly and tell them why.

### 3. Run the prereq check

Run `scripts/check-prereqs-<os>.sh` — NDJSON, one line per requirement. Group results into three buckets:

- **installed** — green check, one line each. Don't dwell.
- **auto-installable** — list with the `install_hint` for each. This is what you're about to install.
- **manual-only** — list with `install_hint`. These need a human; defer to the platform doc for the playbook.

Show counts: "12 installed, 8 to auto-install, 2 need manual steps." Then ask to proceed.

### 4. Auto-install

Run `scripts/install-deps-<os>.sh` (with `--elevated` if and only if the user picked autonomous mode). In friendly/auto-open modes, the script prompts per step on its own — let it. In autonomous mode it runs straight through; relay its stdout to the user as it streams.

If a single install fails, stop. Show the actual stderr. Ask the user what to do — usually it's a network/proxy issue (CA bundle), a sudo prompt timing out, or a flaky upstream. Do not retry blindly.

After install completes, re-run the prereq checker. Anything still in `auto-installable` means an install genuinely failed — investigate before moving on.

### 5. Manual steps

For each `manual-only` requirement, look up the playbook in `platforms/<os>.md` and walk the user through it one at a time:

1. State what they need to do in one or two sentences.
2. In auto-open mode, call `scripts/open-installer.sh` with the relevant URL or `x-apple.systempreferences:` URL.
3. Wait for them to say "done".
4. Re-probe just that requirement (re-run the checker, filter to that record). If still not satisfied, ask what they saw — don't assume.

### 6. Bootstrap

Once the prereq checker reports zero `auto-installable` and zero `manual-only`, you're ready. From the OpenRV checkout directory:

```bash
source ./rvcmds.sh
rvbootstrap
```

This is the OpenRV build wrapper. It handles: configure, dependency download/build, OpenRV build, and packaging. It is verbose and slow; tail its output and surface meaningful events (started X, finished X, failed at Y) rather than every line. Typical wall-clock is 30-90 minutes on a warm cache, several hours from cold.

If `rvbootstrap` fails, the actionable info is almost always in the last 50-100 lines of its output. Show those, name the failing component, and consult `platforms/<os>.md` for known gotchas before suggesting a retry.

### 7. Verify

After `rvbootstrap` succeeds, the OpenRV binary lives under `_build/stage/app/`. The exact name varies by platform:

- macOS: `_build/stage/app/RV.app/Contents/MacOS/RV`
- Linux: `_build/stage/app/bin/rv`
- Windows: `_build\stage\app\bin\rv.exe`

Launch with `--help` to confirm the binary runs and prints version info. Do not launch the GUI from this skill — the user can do that themselves.

## Recovery and partial state

If the user comes back mid-flow ("I killed it, can you continue?"), don't assume. Re-run `detect-platform.sh` and the appropriate `check-prereqs-*.sh`, compare against last known state, and pick up from the first thing that's still incomplete. Mention what's already done so they don't think you're starting over.

## What this skill will not do

- Modify the OpenRV source tree (no patches, no CMakeLists edits — bugs go upstream).
- Run `sudo` outside autonomous mode.
- Bypass the macOS App Management TCC prompt — it must be granted by hand. The plugin only detects and surfaces it.
- Build inside a path that exceeds Windows' MAX_PATH limits — refuses politely and asks the user to move the checkout to a drive root.
- Skip prereq failures with `|| true` or fallbacks. Failures are surfaced.
