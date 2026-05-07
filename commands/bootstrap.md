---
description: Skip checks and run `source rvcmds.sh && rvbootstrap` in the current OpenRV checkout.
---

Escape hatch for users who already have everything installed and just want to run the build wrapper.

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/scripts/detect-platform.sh` and read `openrv_dir` from the JSON. If it's empty, stop: the user is not inside an OpenRV checkout. Tell them to `cd` into one or run `/openrv:build` instead.
2. From `openrv_dir`, run:

   ```bash
   source ./rvcmds.sh && rvbootstrap
   ```

3. Stream output to the user. Surface meaningful events (started/finished phases, errors) rather than every line.
4. If `rvbootstrap` exits non-zero, show the last 50-100 lines of output and consult `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/platforms/<os>.md` for known failure modes before suggesting a retry.
5. On success, point at the built binary under `_build/stage/app/` (exact path varies by OS — see SKILL.md §7).

This command does NOT run prereq checks. If `rvbootstrap` fails for what looks like a missing dependency, run `/openrv:check` to confirm.

User extra args: $ARGUMENTS
