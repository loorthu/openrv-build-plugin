#!/usr/bin/env bash
# Print a single-line JSON object describing the host environment.
# Fields:
#   os            "macos" | "linux" | "windows" | "unknown"
#   distro        "rocky8" | "rocky9" | "rhel" | "fedora" | "ubuntu" | "debian" | "macos" | "windows" | "unknown"
#   arch          "arm64" | "x86_64" | "unknown"
#   pkg_manager   "brew" | "dnf" | "apt" | "pacman" | "winget" | "choco" | "unknown"
#   shell         basename of $SHELL
#   sudo_cached   "true" | "false"   (does `sudo -n true` succeed without prompting?)
#   elevated      "true" | "false"   (running as root, or sudo cached, or known bypass-permissions env vars set)
#   ca_bundle     value of REQUESTS_CA_BUNDLE / CURL_CA_BUNDLE / SSL_CERT_FILE if set, else ""
#   openrv_dir    absolute path of nearest ancestor containing rvcmds.sh, or ""

set -u

os="unknown"
distro="unknown"
arch="unknown"
pkg_manager="unknown"

uname_s="$(uname -s 2>/dev/null || echo unknown)"
uname_m="$(uname -m 2>/dev/null || echo unknown)"

case "$uname_s" in
  Darwin)
    os="macos"; distro="macos"
    [ -x "$(command -v brew)" ] && pkg_manager="brew"
    ;;
  Linux)
    os="linux"
    if [ -r /etc/os-release ]; then
      # shellcheck disable=SC1091
      . /etc/os-release
      case "${ID:-}" in
        rocky)
          case "${VERSION_ID:-}" in
            8*) distro="rocky8" ;;
            9*) distro="rocky9" ;;
            *)  distro="rocky" ;;
          esac ;;
        rhel|centos) distro="rhel" ;;
        fedora)      distro="fedora" ;;
        ubuntu)      distro="ubuntu" ;;
        debian)      distro="debian" ;;
        *)           distro="${ID:-linux}" ;;
      esac
    fi
    if   command -v dnf    >/dev/null 2>&1; then pkg_manager="dnf"
    elif command -v apt    >/dev/null 2>&1; then pkg_manager="apt"
    elif command -v pacman >/dev/null 2>&1; then pkg_manager="pacman"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    os="windows"; distro="windows"
    if   command -v winget >/dev/null 2>&1; then pkg_manager="winget"
    elif command -v choco  >/dev/null 2>&1; then pkg_manager="choco"
    fi
    ;;
esac

case "$uname_m" in
  arm64|aarch64) arch="arm64" ;;
  x86_64|amd64)  arch="x86_64" ;;
esac

shell_name="$(basename "${SHELL:-unknown}")"

sudo_cached="false"
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo_cached="true"
fi

elevated="false"
if [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; then
  elevated="true"
elif [ "$sudo_cached" = "true" ]; then
  elevated="true"
elif [ -n "${CLAUDE_BYPASS_PERMISSIONS:-}" ] || [ -n "${CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS:-}" ]; then
  # Bypass-permissions hint: the harness may set such a var. Fall back to "true" so the
  # skill can offer the autonomous mode; user still has to confirm explicitly.
  elevated="true"
fi

ca_bundle="${REQUESTS_CA_BUNDLE:-${CURL_CA_BUNDLE:-${SSL_CERT_FILE:-}}}"

# Walk upward from CWD looking for rvcmds.sh
openrv_dir=""
dir="$(pwd)"
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
  if [ -f "$dir/rvcmds.sh" ]; then
    openrv_dir="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done

# JSON-escape helper
json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null \
    || printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

printf '{"os":%s,"distro":%s,"arch":%s,"pkg_manager":%s,"shell":%s,"sudo_cached":%s,"elevated":%s,"ca_bundle":%s,"openrv_dir":%s}\n' \
  "$(json_escape "$os")" \
  "$(json_escape "$distro")" \
  "$(json_escape "$arch")" \
  "$(json_escape "$pkg_manager")" \
  "$(json_escape "$shell_name")" \
  "$(json_escape "$sudo_cached")" \
  "$(json_escape "$elevated")" \
  "$(json_escape "$ca_bundle")" \
  "$(json_escape "$openrv_dir")"
