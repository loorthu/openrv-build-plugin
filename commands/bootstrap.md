---
description: Skip checks and run rvbootstrap in the current OpenRV checkout. Asks which VFX Platform year first.
---

Escape hatch for users who already have everything installed and just want to run the build wrapper.

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/scripts/detect-platform.sh` and read `openrv_dir` from the JSON. If it's empty, stop: the user is not inside an OpenRV checkout. Tell them to `cd` into one or run `/openrv:build` instead.
2. Ask which VFX Platform year (`CY2023`, `CY2024`, `CY2025`, `CY2026`). If they don't know, default to `CY2025`. **Do not skip this** — `rvcmds.sh` will block on its `select` menu otherwise.
3. Call the wrapper. **Foreground only — do NOT pass `run_in_background: true`.** The wrapper already tees output to `build.log` inside the OpenRV checkout.

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/scripts/run-bootstrap.sh <openrv_dir> CY<YEAR>
   ```

   Do **not** try to assemble the bash invocation by hand (`bash -c 'source ./rvcmds.sh && rvbootstrap'` will fail because `rvbootstrap` is a bash/zsh alias and doesn't expand in non-interactive bash). Always call the wrapper.

4. If the wrapper exits non-zero, show the last 50-100 lines of `<openrv_dir>/build.log` and consult `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/platforms/<os>.md` for known failure modes before suggesting a retry.
5. On success, point at the built binary under `_build/stage/app/` (exact path varies by OS — see SKILL.md §7).

This command does NOT run prereq checks. If the wrapper fails for what looks like a missing dependency, run `/openrv:check` to confirm.

User extra args: $ARGUMENTS
