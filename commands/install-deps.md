---
description: Install every auto-installable OpenRV dependency. Surfaces (but does not perform) manual-only items.
---

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/scripts/detect-platform.sh` to identify the OS.
2. Run `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/scripts/check-prereqs-<os>.sh` so you know what's already installed.
3. Run `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/scripts/install-deps-<os>.sh`. Pass `--elevated` only if the user is in autonomous mode AND `detect-platform.sh` reported `elevated:true`. Otherwise let the script prompt per step.
4. After install, re-run the prereq checker. Anything still in `auto-installable` failed silently — investigate.
5. List the remaining `manual-only` items with their `install_hint` and a pointer to `platforms/<os>.md`. Do not attempt to perform manual steps in this command — `/openrv-build:build` does that interactively.

User extra args: $ARGUMENTS
