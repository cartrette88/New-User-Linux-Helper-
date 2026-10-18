#!/usr/bin/env bash
# Check installer preflight without downloading the model.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Run this with bash." >&2
  exit 1
fi
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

bash install.sh --help >/dev/null
bash uninstall.sh --help >/dev/null
[[ $(bash install.sh --version) == "1.0.0" ]]
[[ $(bash uninstall.sh --version) == "1.0.0" ]]

if bash install.sh --no-such-option >/dev/null 2>&1; then
  echo "unknown option was accepted" >&2
  exit 1
fi

bash install.sh --check >/dev/null

fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
mkdir -p "${fake}/bin" "${fake}/home"
cat > "${fake}/bin/df" <<'EOF'
#!/bin/sh
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "tmpfs 1000000 900000 1000 90% /"
EOF
chmod 755 "${fake}/bin/df"

set +e
PATH="${fake}/bin:${PATH}" HOME="${fake}/home" bash install.sh --check >"${fake}/out" 2>"${fake}/err"
status=$?
set -e
if [[ $status -eq 0 ]]; then
  echo "low disk space was accepted" >&2
  cat "${fake}/out" >&2
  exit 1
fi
grep -q 'free disk' "${fake}/out"

set +e
PATH="${fake}/bin:${PATH}" HOME="${fake}/home" COMMAND_HELPER_FORCE=1 \
  bash install.sh --check >"${fake}/forced" 2>"${fake}/forced.err"
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "force flag did not override the disk limit" >&2
  cat "${fake}/forced" >&2
  exit 1
fi

echo "preflight ok"
