# Build OpenRV with Claude Code

A plugin for [Claude Code](https://claude.com/claude-code) that compiles [OpenRV](https://github.com/AcademySoftwareFoundation/OpenRV) from source on macOS, Rocky Linux 8/9, or Windows 10/11.

You do **not** need to know what "compile from source" means, or where to download OpenRV from, or what Xcode is. The plugin walks you through every step in plain English and runs as much as it can on its own.

---

## Quickstart

### Before you start, you need

- **Claude Code** installed and signed in. (If you don't have it, see https://claude.com/claude-code.)
- **Internet connection.** The build downloads several gigabytes of source code and dependencies.
- **About 80 GB of free disk space** in your home folder.
- **A few hours.** First-time builds take 1-4 hours depending on your machine. You don't need to babysit it — Claude will tell you when it needs you.
- One operating-system-specific minimum:
  - **macOS** (14 Sonoma, 15 Sequoia, or 26 Tahoe): an **Apple ID** signed into the App Store. The plugin installs everything else.
  - **Rocky Linux 8 or 9** (or RHEL): an account that can use `sudo` (knows the admin password).
  - **Windows 10 or 11**: install **MSYS2** first from https://www.msys2.org/, then launch Claude Code from inside the **MSYS2 MinGW64** shell (`C:\msys64\mingw64.exe`). Sorry — this one step we cannot automate, because Claude Code itself has to be running inside that shell.

### Four commands

Open Claude Code. In the chat, type each of these one at a time and press Enter:

**1. Add this plugin's marketplace.** This tells Claude Code where to find the plugin.

```
/plugin marketplace add https://github.com/loorthu/openrv-build-plugin
```

**2. Install the plugin.**

```
/plugin install openrv-build@openrv-build
```

(Yes, `openrv-build@openrv-build` looks odd. The first is the plugin name; the second is the marketplace name. They happen to be the same.)

**3. Reload plugins.** Required after install — without this, the `/openrv:*` commands won't show up.

```
/reload-plugins
```

**4. Start the guided build.**

```
/openrv:build
```

That's it. From this point Claude will:

- Ask which version of OpenRV you want (just pick the latest unless you have a reason).
- Detect what OS you're on.
- Tell you what's already installed and what it needs to install.
- Ask which automation level you want (pick **Friendly walkthrough** if unsure).
- Install everything it can on its own.
- For anything that needs you (Apple ID for Xcode, a click in System Settings, etc.), explain what to do in plain English and wait until you say "done".
- Run the actual OpenRV build.
- Tell you where the finished program lives when it's done.

You can answer Claude's questions in normal English. You don't need to type commands or know technical terminology.

---

## What if something goes wrong?

- **You can stop at any time** by pressing Ctrl+C or just closing Claude Code. Nothing will be left in a broken state.
- **You can resume later** by running `/openrv:build` again. Claude will check what's already done and pick up from there.
- **If a step fails**, Claude will show you the actual error and stop. It will not silently skip or pretend things worked.

If you get truly stuck, the plugin's GitHub issues page is the right place to ask: https://github.com/loorthu/openrv-build-plugin/issues — paste the error Claude showed you and the OS you're on.

---

## Other commands (optional)

You almost certainly only need `/openrv:build`. These are escape hatches for advanced users:

| Command                  | What it does |
|--------------------------|--------------|
| `/openrv:build`          | The full guided flow above. **Use this one.** |
| `/openrv:check`          | Just check what's installed and what's missing. No installs. |
| `/openrv:install-deps`   | Install everything that can be installed automatically; surface a list of anything that needs you. |
| `/openrv:bootstrap`      | Skip checks and run the OpenRV build directly. Only useful if you've already gone through the full flow once. |

You can also just say "help me build OpenRV" in plain English and Claude will start the guided flow.

---

## Automation levels

When the build starts, Claude asks which level of automation you want:

- **Friendly walkthrough** (recommended for first-timers): Claude pauses before each step and waits for you to say "go".
- **Auto-open mode**: Same as friendly, but Claude also opens installer pages, the App Store, or System Settings panes for you so you don't have to find them.
- **Fully autonomous**: Only available when Claude Code is running with bypass-permissions enabled. Claude runs admin commands directly without asking each time. You'll see a one-screen warning before the first install listing exactly what will happen.

If you don't know which to pick, pick **Friendly walkthrough**.

---

## What still needs you, by platform

Some things genuinely cannot be automated. The plugin will call these out clearly when it gets to them — you don't need to memorize this list.

| Platform | Always-manual items |
|----------|--------------------|
| macOS    | Installing the full Xcode app from the App Store (needs your Apple ID), and granting the **App Management** permission to your terminal in System Settings. |
| Linux    | Typing your `sudo` password when prompted. |
| Windows  | Approving the User Account Control (UAC) prompt when MSVC build tools install. Also: your OpenRV folder must live somewhere short like `C:\OpenRV`, not deep inside `Documents\GitHub\…`, because of Windows path-length limits. |

---

## Corporate proxies and SSL inspection

If your work computer goes through a corporate firewall that inspects SSL traffic (e.g. Netskope, Zscaler), and you've already set one of `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`, or `SSL_CERT_FILE` to your company's CA bundle, the plugin will pick those up automatically and pass them through to all dependency downloads.

If you haven't configured any of those and your company uses an inspecting proxy, ask IT for a CA bundle file path and set it before launching Claude Code:

```bash
export REQUESTS_CA_BUNDLE=/path/to/company-ca-bundle.pem
export CURL_CA_BUNDLE=/path/to/company-ca-bundle.pem
export SSL_CERT_FILE=/path/to/company-ca-bundle.pem
```

---

## License

Apache-2.0. See [LICENSE](LICENSE).

## Contributing

Issues and pull requests are welcome at https://github.com/loorthu/openrv-build-plugin. The plugin shells out to OpenRV's own [rvcmds.sh](https://github.com/AcademySoftwareFoundation/OpenRV/blob/main/rvcmds.sh) for the actual build, so most fixes belong upstream in OpenRV; the plugin's job is environment setup, dependency installation, and walkthrough pacing.
