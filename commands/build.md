---
description: Full guided OpenRV build — pick version, detect platform, install deps, bootstrap, verify.
---

Run the `build-openrv` skill end-to-end:

1. Ask which OpenRV version to build (run `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/scripts/pick-openrv-version.sh list` and present choices).
2. Detect platform via `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/scripts/detect-platform.sh`.
3. Run prereq check, install everything auto-installable, walk the user through manual steps.
4. `source rvcmds.sh && rvbootstrap` from the OpenRV checkout.
5. Verify the resulting binary launches with `--help`.

Follow `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/SKILL.md` for the full operating procedure, including the friendly / auto-open / autonomous mode selection. Use `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/platforms/<os>.md` for platform-specific gotchas.

User extra args: $ARGUMENTS
