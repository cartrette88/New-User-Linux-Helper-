#!/usr/bin/env bash
# Remove Command Helper for the current user. Does not use sudo.
# Safe to run more than once.
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  printf 'Run this script with bash.\n' >&2
  exit 1
fi

usage() {
  cat << 'EOF'
Usage: uninstall.sh
       command-helper-uninstall

Removes Command Helper for the current user. Does not use sudo.

Deletes the program, the app-menu entry, the desktop icon, the PATH
snippet, llama.cpp, and the downloaded model (about 2.5 GB).

Safe to run more than once.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    printf 'Unknown option: %s\n' "$1" >&2
    exit 1
    ;;
esac

if [ "$(id -u)" -eq 0 ]; then
  printf 'Run this as your normal user, without sudo.\n' >&2
  exit 1
fi

say() { printf '==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

LLAMA_DIR="${HOME}/.local/opt/llama.cpp/llama-b11716"
SHARE_DIR="${HOME}/.local/share/command-helper"
STATE_DIR="${HOME}/.local/state/command-helper"
CONFIG_DIR="${HOME}/.config/command-helper"
APPS_DIR="${HOME}/.local/share/applications"

desktop_dir() {
  local d="${HOME}/Desktop"
  local dirs="${HOME}/.config/user-dirs.dirs"
  if [ -f "$dirs" ]; then
    local raw
    raw=$(awk -F= '/^XDG_DESKTOP_DIR=/ {print substr($0, index($0, "=") + 1)}' "$dirs" | head -n 1)
    raw=${raw%\"}
    raw=${raw#\"}
    raw=${raw%\'}
    raw=${raw#\'}
    raw=${raw/\$HOME/$HOME}
    if [ -n "$raw" ]; then
      d=$raw
    fi
  fi
  printf '%s\n' "$d"
}

stop_server() {
  local pid args
  while read -r pid args; do
    [ -n "$pid" ] || continue
    case "$args" in
      *"${LLAMA_DIR}/llama-server"*)
        kill "$pid" 2>/dev/null || true
        ;;
    esac
  done < <(ps -u "$(id -u)" -o pid=,args= 2>/dev/null || true)
}

remove_snippet() {
  local file=$1
  [ -f "$file" ] || return 0
  local tmp
  tmp=$(mktemp)
  awk '
    /# >>> command-helper >>>/ {skip=1; next}
    /# <<< command-helper <<</ {skip=0; next}
    skip==0 {print}
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

say "Removing Command Helper"
stop_server
info "Stopped the local model server if it was running."

rm -f \
  "${HOME}/.local/bin/ask" \
  "${HOME}/.local/bin/command-helper-launch" \
  "${HOME}/.local/bin/command-helper-uninstall"
rm -f "${APPS_DIR}/command-helper.desktop"
rm -f "$(desktop_dir)/command-helper.desktop"

rm -rf "$LLAMA_DIR" "$SHARE_DIR" "$STATE_DIR" "$CONFIG_DIR"
rmdir "${HOME}/.local/opt/llama.cpp" 2>/dev/null || true

remove_snippet "${HOME}/.bashrc"
remove_snippet "${HOME}/.profile"
remove_snippet "${HOME}/.zshrc"

info "Removed the program, menu entry, desktop icon, model, and llama.cpp."
info "Removed the PATH snippet from shell startup files, when it was present."
printf 'Command Helper is uninstalled.\n'
