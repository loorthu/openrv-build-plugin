---
name: build-openrv
description: Guide a user through compiling OpenRV from source on macOS, Rocky Linux 8/9, or Windows 10/11. Detects platform, runs prereq checks, installs everything that can be installed automatically (brew, dnf/apt, winget/choco, pacman, pip, rustup, aqtinstall), and walks the user through anything that genuinely requires a human (Apple ID for Xcode, MSVC component picker, macOS App Management TCC grant). Trigger on requests like "build OpenRV", "compile OpenRV", "set up OpenRV from source", or when the user is in a directory containing rvcmds.sh and asks for help getting it to build.
---

# Build OpenRV from source

You are guiding a user through compiling OpenRV. This is a long process (~30-90 minutes wall clock once dependencies are in place; first-time setup can be several hours on a clean machine). Most users invoking this skill are not C++ build experts. Be patient, explain what each step does in plain language, and never silently skip a check.

## STOP — read before any tool calls

These are the mistakes that have actually happened in past runs of this skill. Read them now, before you run anything.

1. **Never `run_in_background: true` on `rvbootstrap`.** Not even for "streaming." Backgrounded shells have their stdin disconnected; `rvcmds.sh` is interactive (it prompts for VFX year, branch confirms on dirty trees, etc.) and a backgrounded prompt becomes an infinite-loop log file that fills disk. Always foreground.
2. **Never assemble the bootstrap command by hand.** Use `scripts/run-bootstrap.sh <openrv_dir> <CY_YEAR>` (see step 6). The wrapper handles `cd`, `RV_VFX_PLATFORM` export, alias expansion (`rvbootstrap` is a bash/zsh alias, not a function — it does not expand in non-interactive bash without `shopt -s expand_aliases`), foreground execution, and logging. If you find yourself writing `bash -c 'source ./rvcmds.sh && rvbootstrap'`, stop — it will fail.
3. **Never pipe answers to interactive prompts** (`echo "2" | ...`). The menu order can change. Always set the corresponding env var (`RV_VFX_PLATFORM=CY2024`) so the prompt is skipped entirely.
4. **Never run anything without the user's checkout dir as CWD.** If you don't `cd`, `source ./rvcmds.sh` errors. The wrapper does this for you; if you bypass the wrapper, you must do it yourself.
5. **Always ask both step-1 questions** even if the user is already inside an OpenRV checkout. They may want a different ref or VFX year than last time.

## Operating principles

1. **One step at a time.** Detect → report → confirm → act → verify. Do not chain installs. If something fails, stop and surface the actual error before retrying.
2. **Idempotent.** Every script in `scripts/` can be re-run safely. If the user re-invokes the skill mid-flow, re-run the relevant check rather than assuming prior state.
3. **Honor the automation level.** The user picks one at the start (see §Modes). Do not silently escalate.
4. **Don't invent versions, package names, or flags.** All hard data lives in `scripts/` and `platforms/<os>.md`. If a script reports something you don't recognize, ask the user rather than guessing.
5. **Surface the OpenRV build wrapper, don't replace it.** The actual build is `scripts/run-bootstrap.sh`, which sources `rvcmds.sh` and runs `rvbootstrap`. The skill's job is environment, dependencies, and pacing — not reimplementing the build.

## Directory layout

- `scripts/detect-platform.sh` — emits one-line JSON about OS, arch, package manager, elevated state, CA bundle, and whether the CWD is already inside an OpenRV checkout.
- `scripts/pick-openrv-version.sh list` — lists recent upstream tags + `main`.
- `scripts/pick-openrv-version.sh prepare <ref> [<dir>]` — clones or checks out the chosen ref. Prints final absolute path on stdout.
- `scripts/check-prereqs-{macos,linux,windows}.sh` — emit NDJSON, one record per requirement: `{requirement, min_version, found_version, status, install_hint}`. `status` is `installed`, `auto-installable`, or `manual-only`.
- `scripts/install-deps-{macos,linux,windows}.sh` — install everything auto-installable. Accepts `--only <name>` to install one item, or `--elevated` to skip per-step confirmations (only pass this when the user is in fully-autonomous mode).
- `scripts/install-qt.sh` — headless Qt 6.5.3 install via aqtinstall. Prints resolved `QT_HOME` on stdout.
- `scripts/run-bootstrap.sh <openrv_dir> <vfx_year> [<qt_home>] [<build_type>]` — the **only** correct way to invoke `rvbootstrap`. Handles cd, env vars, alias expansion, foreground, and logging. Step 6 calls this.
- `scripts/open-installer.sh <url-or-path>` — opens a URL or file in the default handler (auto-open mode only).
- `platforms/macos.md`, `platforms/linux.md`, `platforms/windows.md` — per-platform manual-step playbooks. Read the relevant one once you know the OS.

## Modes

Ask the user once, near the start. Default to **friendly walkthrough** if they don't pick.

- **friendly** (default) — Pause before every install. Show what's about to happen, wait for "go". For manual steps, explain what to click and wait for "done".
- **auto-open** — Same as friendly, but call `scripts/open-installer.sh` to open App Store / installer pages / System Settings panes for the user.
- **autonomous** — Only offer this if `detect-platform.sh` reports `"elevated":"true"`. Pass `--elevated` to install scripts so they don't prompt. Still show a one-screen warning before the first sudo/admin command listing what will run, and require an explicit "yes, proceed" before the first install. After that, run without per-step confirmation but report each install as it happens.

## The flow

### 1. Pick the build target — TWO questions, always asked

You must ask BOTH of these at the start, **even if the user is already inside an OpenRV checkout**. Don't skip the questions just because a checkout exists — they may want a different ref or a different VFX Platform year than last time.

**1a. Which OpenRV ref to build?**

Run `scripts/pick-openrv-version.sh list`. Show the user:
- Current checkout (if any) and its ref.
- Up to 10 recent release tags.
- The `main` branch as an option.

Ask which to build. If the CWD is already an OpenRV checkout at the requested ref, skip prepare. Otherwise run `scripts/pick-openrv-version.sh prepare <ref> [<target_dir>]` and `cd` into the printed path for the rest of the session. If they want a target directory other than CWD/`OpenRV`, ask and pass it as the third arg.

**1b. Which VFX Platform year?**

OpenRV's `rvbootstrap` requires `RV_VFX_PLATFORM` to be set to one of `CY2023`, `CY2024`, `CY2025`, or `CY2026`. If you don't set it before running bootstrap, the script will prompt interactively — and if you ran it with stdin disconnected (background, `<&-`, etc.) it will spin forever printing the menu.

The choice determines which Qt version the build needs, so the prereq check (step 3) must know it:

| VFX year | Qt requirement | Notes |
|----------|----------------|-------|
| CY2023   | Qt 5.15        | Legacy. Don't recommend unless the user has a specific reason. |
| CY2024   | Qt 6.5.3       | Stable. Default for v3.0.x and earlier. |
| CY2025   | Qt 6.5.3       | Current default for v3.1.x / v3.2.x. **Recommend this unless told otherwise.** |
| CY2026   | Qt 6.8.x       | Newest. Requires Qt 6.8 (the install scripts default to 6.5.3 — pass `--version 6.8.x` to `install-qt.sh` if user picks CY2026). |

Ask the user which year. If they don't know, default to CY2025. Remember the choice for steps 3 (Qt detection) and 6 (export `RV_VFX_PLATFORM`).

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

**Qt version note:** the bundled `install-qt.sh` defaults to Qt 6.5.3, which matches CY2024/CY2025. If the user picked CY2026 in step 1b, run `install-deps` with `--only` arguments to install everything *except* Qt, then call `install-qt.sh --version 6.8.1` directly and remember the printed `QT_HOME` for step 6. If they picked CY2023 (legacy), `install-qt.sh` does not cover Qt 5 — tell the user they need to install Qt 5.15 by hand from https://www.qt.io/offline-installers; this is the one VFX-year combination we don't automate.

If a single install fails, stop. Show the actual stderr. Ask the user what to do — usually it's a network/proxy issue (CA bundle), a sudo prompt timing out, or a flaky upstream. Do not retry blindly.

After install completes, re-run the prereq checker. Anything still in `auto-installable` means an install genuinely failed — investigate before moving on.

### 5. Manual steps

For each `manual-only` requirement, look up the playbook in `platforms/<os>.md` and walk the user through it one at a time:

1. State what they need to do in one or two sentences.
2. In auto-open mode, call `scripts/open-installer.sh` with the relevant URL or `x-apple.systempreferences:` URL.
3. Wait for them to say "done".
4. Re-probe just that requirement (re-run the checker, filter to that record). If still not satisfied, ask what they saw — don't assume.

### 6. Bootstrap

Once the prereq checker reports zero `auto-installable` and zero `manual-only`, you're ready.

**Call the wrapper script. Do not assemble the bash invocation by hand.** The five mistakes the model has historically made (no `cd`, missing `RV_VFX_PLATFORM`, backgrounded, alias-not-expanded, prompt-piped) are all handled by `scripts/run-bootstrap.sh`. Your job is to call it with the right arguments.

Arguments:
1. `<openrv_dir>` — the absolute path from step 1a.
2. `<vfx_year>` — the choice from step 1b (`CY2023`, `CY2024`, `CY2025`, or `CY2026`).
3. `<qt_home>` (optional) — only pass this if you installed Qt 6.8 separately for CY2026 (see step 4 Qt note). Otherwise leave it off; the script lets `rvcmds.sh` find Qt at the default location.
4. `<build_type>` (optional) — `Release` (default) or `Debug`.

Invoke it. **Foreground only — do not pass `run_in_background: true` to the Bash tool.** If you want to give the user a log, the script already tees to `<openrv_dir>/build.log`; you don't need to add your own redirect.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/scripts/run-bootstrap.sh <openrv_dir> CY<YEAR>
```

This is the OpenRV build wrapper. It handles: configure, dependency download/build, OpenRV build, and packaging. It is verbose and slow; surface meaningful events (started X, finished X, failed at Y) rather than every line. Typical wall-clock is 30-90 minutes on a warm cache, several hours from cold.

If `run-bootstrap.sh` exits non-zero, the actionable info is in `<openrv_dir>/build.log` (the script printed the path on exit). Show the last 50-100 lines, name the failing component, and consult `platforms/<os>.md` for known gotchas before suggesting a retry. For a quick triage, the user can also run `rverrsummary` inside an interactive shell after `cd <openrv_dir> && source ./rvcmds.sh`.

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
