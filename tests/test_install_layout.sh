#!/usr/bin/env bash
# Install the user-facing files into a fake home folder, then uninstall them.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Run this with bash." >&2
  exit 1
fi
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

export HOME="${tmpdir}/home"
export XDG_CONFIG_HOME="${HOME}/.config"
unset XDG_DESKTOP_DIR || true
mkdir -p "${HOME}/Desktop" "${XDG_CONFIG_HOME}"
printf '%s\n' 'echo keep-me' > "${HOME}/.bashrc"
printf '%s\n' '# existing profile' > "${HOME}/.profile"
printf '%s\n' '# zsh user' > "${HOME}/.zshrc"

# shellcheck source=install.sh
source "${root}/install.sh"
install_user_files
refresh_user_path

[[ -x ${HOME}/.local/bin/ask ]]
[[ -x ${HOME}/.local/bin/command-helper-launch ]]
[[ -x ${HOME}/.local/bin/command-helper-uninstall ]]
cmp -s "${root}/bin/ask" "${HOME}/.local/bin/ask"

desktop_app="${HOME}/.local/share/applications/command-helper.desktop"
desktop_icon="${HOME}/Desktop/command-helper.desktop"
[[ -f $desktop_app ]]
[[ -f $desktop_icon ]]
grep -q "${HOME}/.local/bin/command-helper-launch" "$desktop_app"
grep -q "${HOME}/.local/bin/command-helper-launch" "$desktop_icon"
if grep -q '@EXEC@' "$desktop_app"; then
  echo "desktop file still has the placeholder" >&2
  exit 1
fi

begin='BEGIN command-helper PATH (added by the installer)'
[[ $(grep -c "$begin" "${HOME}/.bashrc") -eq 1 ]]
[[ $(grep -c "$begin" "${HOME}/.profile") -eq 1 ]]
[[ $(grep -c "$begin" "${HOME}/.zshrc") -eq 1 ]]
grep -q 'echo keep-me' "${HOME}/.bashrc"

env -u XDG_DESKTOP_DIR HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
  bash "${root}/uninstall.sh" --yes

[[ ! -e ${HOME}/.local/bin/ask ]]
[[ ! -e ${HOME}/.local/bin/command-helper-launch ]]
[[ ! -e ${HOME}/.local/bin/command-helper-uninstall ]]
[[ ! -e $desktop_app ]]
[[ ! -e $desktop_icon ]]
if grep -q "$begin" "${HOME}/.bashrc"; then
  echo "PATH block remained in bashrc" >&2
  exit 1
fi
grep -q 'echo keep-me' "${HOME}/.bashrc"
grep -q 'existing profile' "${HOME}/.profile"

echo "install layout ok"
