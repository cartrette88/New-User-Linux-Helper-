#!/usr/bin/env bash
# Remove Command Helper from the current user account. Does not use sudo.
# SPDX-License-Identifier: MIT
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this uninstaller with bash:  bash uninstall.sh" >&2
  exit 1
fi
set -euo pipefail

VERSION="1.0.0"
LLAMA_VERSION="b11716"

PATH_BEGIN='# BEGIN command-helper PATH (added by the installer)'
PATH_END='# END command-helper PATH'

BIN_DIR=""
LLAMA_PARENT=""
LLAMA_DIR=""
SHARE_DIR=""
STATE_DIR=""
APPS_FILE=""
CACHE_DIR=""

say() { printf '%s\n' "$*"; }

die() {
  printf '\nError: %s\n' "$1" >&2
  shift || true
  local line
  for line in "$@"; do
    printf '       %s\n' "$line" >&2
  done
  exit 1
}

usage() {
  cat <<EOF
Usage: bash uninstall.sh [--yes]

Remove Command Helper, the local model, and the llama.cpp files it downloaded.
Your documents and other programs are left alone. This does not use sudo.

  --yes      Remove without asking. Use this only when you mean it.
  --help     Show this message.
  --version  Show the uninstaller version.
EOF
}

set_paths() {
  BIN_DIR="${HOME}/.local/bin"
  LLAMA_PARENT="${HOME}/.local/opt/llama.cpp"
  LLAMA_DIR="${LLAMA_PARENT}/llama-${LLAMA_VERSION}"
  SHARE_DIR="${HOME}/.local/share/command-helper"
  STATE_DIR="${HOME}/.local/state/command-helper"
  APPS_FILE="${HOME}/.local/share/applications/command-helper.desktop"
  CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/command-helper"
}

desktop_dir() {
  local d=""
  if [[ -n ${XDG_DESKTOP_DIR:-} && -d ${XDG_DESKTOP_DIR} ]]; then
    d=$XDG_DESKTOP_DIR
  elif command -v xdg-user-dir >/dev/null 2>&1; then
    d=$(xdg-user-dir DESKTOP 2>/dev/null || true)
  fi
  if [[ -n $d && -d $d ]]; then
    case $d in
      "${HOME}"/*)
        printf '%s\n' "$d"
        return 0
        ;;
    esac
  fi
  if [[ -d ${HOME}/Desktop ]]; then
    printf '%s\n' "${HOME}/Desktop"
    return 0
  fi
  return 1
}

strip_path_block() {
  local file=$1 tmp
  [[ -f $file ]] || return 0
  if ! grep -qF "$PATH_BEGIN" "$file" || ! grep -qF "$PATH_END" "$file"; then
    return 0
  fi
  tmp=$(mktemp)
  awk -v b="$PATH_BEGIN" -v e="$PATH_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    skip { next }
    { print }
  ' "$file" > "$tmp"
  chmod --reference="$file" "$tmp" 2>/dev/null || chmod 644 "$tmp"
  mv -f -- "$tmp" "$file"
}

strip_user_path() {
  local file
  for file in "${HOME}/.bashrc" "${HOME}/.profile" "${HOME}/.zshrc"; do
    strip_path_block "$file"
  done
}

refuse_surprise_path() {
  local path=$1 allowed=0
  if [[ -z $path || $path == "/" || $path == "$HOME" ]]; then
    die "Refusing to remove ${path:-an empty path}."
  fi
  case $path in
    "${HOME}/.local/opt/llama.cpp/llama-${LLAMA_VERSION}"|\
    "${HOME}/.local/share/command-helper"|\
    "${HOME}/.local/state/command-helper")
      allowed=1
      ;;
  esac
  if [[ $path == "$CACHE_DIR" && $CACHE_DIR == "${HOME}"/* ]]; then
    allowed=1
  fi
  if [[ $allowed -eq 0 ]]; then
    die "Refusing to remove an unexpected path: ${path}"
  fi
}

remove_tree() {
  local path=$1
  [[ -e $path || -L $path ]] || return 0
  refuse_surprise_path "$path"
  if [[ -L $path ]]; then
    rm -f -- "$path"
    return 0
  fi
  rm -rf -- "$path"
}

anything_installed() {
  local file
  if [[ -e ${BIN_DIR}/ask || -e ${BIN_DIR}/command-helper-launch || -e ${BIN_DIR}/command-helper-uninstall ]]; then
    return 0
  fi
  if [[ -e $APPS_FILE || -e $LLAMA_DIR || -e $SHARE_DIR || -e $STATE_DIR || -e $CACHE_DIR ]]; then
    return 0
  fi
  if [[ -f ${HOME}/Desktop/command-helper.desktop ]]; then
    return 0
  fi
  for file in "${HOME}/.bashrc" "${HOME}/.profile" "${HOME}/.zshrc"; do
    if [[ -f $file ]] && grep -qF "$PATH_BEGIN" "$file"; then
      return 0
    fi
  done
  return 1
}

confirm() {
  local ans
  say "This removes Command Helper from your user account."
  say "It deletes the program, the app-menu entry, the desktop icon,"
  say "the language model (about 2.5 GB), and the llama.cpp files it downloaded."
  say "Your documents and other programs are left alone."
  say "This does not use sudo."
  say ""
  if [[ ! -t 0 ]]; then
    die "Run the uninstaller in a terminal so it can ask first, or pass --yes."
  fi
  if ! read -r -p "Remove Command Helper? [y/N] " ans; then
    printf '\n'
    die "No answer, so nothing was removed."
  fi
  case ${ans,,} in
    y|yes) ;;
    *)
      say "Not removed."
      exit 0
      ;;
  esac
}

remove_installed_files() {
  local desk=""
  rm -f -- "${BIN_DIR}/ask" "${BIN_DIR}/command-helper-launch" "${BIN_DIR}/command-helper-uninstall"
  rm -f -- "$APPS_FILE"
  if desk=$(desktop_dir); then
    rm -f -- "${desk}/command-helper.desktop"
  fi
  rm -f -- "${HOME}/Desktop/command-helper.desktop"
  remove_tree "$LLAMA_DIR"
  rmdir "$LLAMA_PARENT" 2>/dev/null || true
  remove_tree "$SHARE_DIR"
  remove_tree "$STATE_DIR"
  remove_tree "$CACHE_DIR"
  strip_user_path
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${HOME}/.local/share/applications" >/dev/null 2>&1 || true
  fi
}

main() {
  local assume_yes=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help) usage; exit 0 ;;
      --version) printf '%s\n' "$VERSION"; exit 0 ;;
      --yes) assume_yes=1; shift ;;
      *) die "Unknown option: $1" "Try: bash uninstall.sh --help" ;;
    esac
  done

  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    die "Run this as your normal user, without sudo."
  fi

  set_paths
  if ! anything_installed; then
    say "Command Helper is not installed for this user."
    exit 0
  fi
  if [[ $assume_yes -eq 0 ]]; then
    confirm
  fi
  remove_installed_files
  say "Command Helper is removed."
  say "Open a new terminal so the command path refreshes."
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
