---
description: Run the OpenRV prerequisites check and report the status. Does not install anything.
---

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/scripts/detect-platform.sh` to identify the OS.
2. Run the matching `${CLAUDE_PLUGIN_ROOT}/skills/build-openrv/scripts/check-prereqs-<os>.sh`.
3. Parse the NDJSON output and present three groups:
   - **Installed** — count only, no detail unless asked.
   - **Auto-installable** — list with the `install_hint` for each.
   - **Manual-only** — list with the `install_hint` and a one-line note pointing at `platforms/<os>.md` for the playbook.

Do not install anything. Do not call any of the `install-deps-*.sh` scripts. End with: "Run `/openrv:install-deps` to auto-install the green items, or `/openrv:build` for the full guided flow."

User extra args: $ARGUMENTS
