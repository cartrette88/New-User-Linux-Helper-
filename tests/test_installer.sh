#!/usr/bin/env bash
# Tests that do not download llama.cpp or the model.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/common.sh
source "${ROOT}/scripts/common.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "expected [$2] got [$1]"
}

test_arch() {
  local out
  out=$(ch_asset_for_arch x86_64)
  case "$out" in
    *"8c08b19bee40d118b803d58fd8f6633ba311ce3c7f1f0138262e636f02aa11f0"*) ;;
    *) fail "x86_64 asset: $out" ;;
  esac
  out=$(ch_asset_for_arch aarch64)
  case "$out" in
    *"8cbdc3e5df1e7f37de5c1be4ef93dd4fadea9e0b958f92af6f9c4c84c9882519"*) ;;
    *) fail "arm64 asset: $out" ;;
  esac
  if ch_asset_for_arch ppc64le >/dev/null; then
    fail "unknown architecture was accepted"
  fi
}

test_download_verified() {
  local tmp sha dest
  tmp=$(mktemp -d)
  printf 'hello-model' > "${tmp}/payload"
  sha=$(sha256sum -- "${tmp}/payload" | awk '{print $1}')
  dest="${tmp}/out/file"
  ch_download_verified "file://${tmp}/payload" "$dest" "$sha" "sample file" >/dev/null
  cmp -s "${tmp}/payload" "$dest" || fail "downloaded file did not match"
  ch_download_verified "file://${tmp}/payload" "$dest" "$sha" "sample file" >/dev/null
  if (
    ch_download_verified "file://${tmp}/payload" "${tmp}/bad" \
      "0000000000000000000000000000000000000000000000000000000000000000" \
      "bad file" >/dev/null 2>&1
  ); then
    fail "a bad checksum was accepted"
  fi
  [ ! -e "${tmp}/bad" ] || fail "a bad download was kept"
  [ ! -e "${tmp}/bad.partial" ] || fail "a bad partial download was kept"
  rm -rf "$tmp"
}

test_sha256() {
  local tmp exp
  tmp=$(mktemp)
  printf 'hello' > "$tmp"
  exp=$(sha256sum -- "$tmp" | awk '{print $1}')
  ch_sha256_matches "$tmp" "$exp" || fail "matching checksum rejected"
  if ch_sha256_matches "$tmp" "0000000000000000000000000000000000000000000000000000000000000000"; then
    fail "bad checksum accepted"
  fi
  rm -f "$tmp"
}

test_classes() {
  assert_eq "$(ch_memory_class 1000000)" "low"
  assert_eq "$(ch_memory_class 4000000)" "tight"
  assert_eq "$(ch_memory_class 8000000)" "ok"
  assert_eq "$(ch_disk_class 10 20)" "short"
  assert_eq "$(ch_disk_class 20 20)" "ok"
  assert_eq "$(ch_disk_class 30 20)" "ok"
}

test_bad_model_is_removed() {
  (
    export HOME CH_MODEL_STATE
    HOME=$(mktemp -d)
    CH_MODEL_STATE=""
    mkdir -p "$(dirname "$(ch_model_path)")"
    printf 'not-the-model\n' > "$(ch_model_path)"
    printf 'partial\n' > "$(ch_model_path).partial"
    ch_prepare_model_file >/dev/null 2>&1
    [ ! -e "$(ch_model_path)" ] || fail "bad model file was kept"
    [ ! -e "$(ch_model_path).partial" ] || fail "partial download was kept"
    assert_eq "$CH_MODEL_STATE" "no"
    rm -rf "$HOME"
  )
}

test_required_bytes_without_downloads() {
  (
    export HOME
    HOME=$(mktemp -d)
    assert_eq "$(ch_required_bytes)" "3500000000"
    rm -rf "$HOME"
  )
}

test_desktop_render() {
  local tmp out exec_path
  tmp=$(mktemp -d)
  exec_path="${tmp}/bin/command-helper-launch"
  out="${tmp}/out.desktop"
  ch_render_desktop "${ROOT}/share/command-helper.desktop" "$out" "$exec_path"
  grep -F -x -q "Exec=${exec_path}" "$out" || fail "Exec was not rewritten"
  grep -F -x -q "TryExec=${exec_path}" "$out" || fail "TryExec was not rewritten"
  grep -F -x -q "Name=Command Helper" "$out" || fail "Name was lost"
  local spaced="${tmp}/My Desktop/command-helper-launch"
  ch_render_desktop "${ROOT}/share/command-helper.desktop" "$out" "$spaced"
  grep -F -x -q "Exec=\"${spaced}\"" "$out" || fail "spaced Exec not quoted"
  rm -rf "$tmp"
}

test_repo_desktop_uses_path_lookup() {
  grep -q '^Exec=command-helper-launch$' "${ROOT}/share/command-helper.desktop" \
    || fail "repo desktop file should look up the command on PATH"
}

test_desktop_dir_from_user_dirs() {
  (
    export HOME
    HOME=$(mktemp -d)
    mkdir -p "${HOME}/.config"
    printf 'XDG_DESKTOP_DIR="$HOME/My Desktop"\n' > "${HOME}/.config/user-dirs.dirs"
    assert_eq "$(ch_desktop_dir)" "${HOME}/My Desktop"
    rm -rf "$HOME"
  )
}

test_path_snippet_once() {
  (
    export HOME
    HOME=$(mktemp -d)
    ch_append_path_snippet "${HOME}/.bashrc"
    ch_append_path_snippet "${HOME}/.bashrc"
    assert_eq "$(grep -c '>>> command-helper >>>' "${HOME}/.bashrc")" "1"
    grep -q 'HOME/.local/bin' "${HOME}/.bashrc" || fail "snippet missing PATH line"
    rm -rf "$HOME"
  )
}

test_install_scripts_only() {
  (
    export HOME
    HOME=$(mktemp -d)
    ch_install_scripts "$ROOT"
    ch_install_desktop "$ROOT"
    [ -x "${HOME}/.local/bin/ask" ] || fail "ask was not installed"
    [ -x "${HOME}/.local/bin/command-helper-launch" ] || fail "launcher was not installed"
    [ -x "${HOME}/.local/bin/command-helper-uninstall" ] || fail "uninstaller was not installed"
    grep -F -x -q "Exec=${HOME}/.local/bin/command-helper-launch" \
      "${HOME}/.local/share/applications/command-helper.desktop" \
      || fail "menu entry path was not filled in"
    rm -rf "$HOME"
  )
}

test_uninstall() {
  (
    export HOME
    HOME=$(mktemp -d)
    mkdir -p \
      "${HOME}/.local/bin" \
      "${HOME}/.local/share/command-helper/models" \
      "${HOME}/.local/opt/llama.cpp/llama-b11716" \
      "${HOME}/.local/share/applications" \
      "${HOME}/.local/state/command-helper" \
      "${HOME}/.config/command-helper" \
      "${HOME}/Desktop"
    printf 'ask\n' > "${HOME}/.local/bin/ask"
    printf 'launch\n' > "${HOME}/.local/bin/command-helper-launch"
    printf 'uninstall\n' > "${HOME}/.local/bin/command-helper-uninstall"
    printf 'model\n' > "${HOME}/.local/share/command-helper/models/model.gguf"
    printf 'server\n' > "${HOME}/.local/opt/llama.cpp/llama-b11716/llama-server"
    printf 'menu\n' > "${HOME}/.local/share/applications/command-helper.desktop"
    printf 'desk\n' > "${HOME}/Desktop/command-helper.desktop"
    printf 'cuda\n' > "${HOME}/.config/command-helper/backend"
    cat > "${HOME}/.bashrc" << 'EOF'
keep-before
# >>> command-helper >>>
export PATH="$HOME/.local/bin:$PATH"
# <<< command-helper <<<
keep-after
EOF
    bash "${ROOT}/uninstall.sh" >/dev/null
    [ ! -e "${HOME}/.local/bin/ask" ] || fail "ask still installed"
    [ ! -e "${HOME}/.local/share/command-helper" ] || fail "model dir still installed"
    [ ! -e "${HOME}/.local/opt/llama.cpp/llama-b11716" ] || fail "llama.cpp still installed"
    [ ! -e "${HOME}/Desktop/command-helper.desktop" ] || fail "desktop icon still installed"
    [ ! -e "${HOME}/.config/command-helper" ] || fail "config still installed"
    grep -q 'keep-before' "${HOME}/.bashrc" || fail "bashrc lost earlier lines"
    grep -q 'keep-after' "${HOME}/.bashrc" || fail "bashrc lost later lines"
    if grep -q 'command-helper' "${HOME}/.bashrc"; then
      fail "PATH snippet still in bashrc"
    fi
    bash "${ROOT}/uninstall.sh" >/dev/null
    rm -rf "$HOME"
  )
}

test_help_and_version() {
  local version
  version=$(python3 "${ROOT}/bin/ask" --version)
  assert_eq "$version" "1.0.0"
  python3 "${ROOT}/bin/ask" --help >/dev/null
  version=$(bash "${ROOT}/install.sh" --version)
  assert_eq "$version" "1.0.0"
  version=$(bash "${ROOT}/command-helper-installer.sh" --version)
  assert_eq "$version" "1.0.0"
  bash "${ROOT}/install.sh" --help | grep -q 'Does not use sudo' || fail "help missing sudo note"
  bash "${ROOT}/command-helper-installer.sh" --help | grep -q "$MODEL_SHA256" || fail "help missing model checksum"
  bash "${ROOT}/uninstall.sh" --help >/dev/null
  if bash "${ROOT}/install.sh" --nope >/dev/null 2>&1; then
    fail "unknown option was accepted"
  fi
}

test_payloads_match_sources() {
  python3 - "$ROOT" << 'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
text = (root / "command-helper-installer.sh").read_text(encoding="utf-8")

def payload(marker, rel):
    match = re.search(
        r"cat > \"\$dest/" + re.escape(rel) + r"\" << '" + marker + r"'\n(.*)\n" + marker + r"\n",
        text,
        re.S,
    )
    if not match:
        raise SystemExit(f"missing payload {rel}")
    embedded = match.group(1) + "\n"
    source = (root / rel).read_text(encoding="utf-8")
    if not source.endswith("\n"):
        source += "\n"
    if embedded != source:
        raise SystemExit(f"embedded {rel} does not match the source file")

payload("CH_EMBED_ASK", "bin/ask")
payload("CH_EMBED_LAUNCH", "bin/command-helper-launch")
payload("CH_EMBED_DESKTOP", "share/command-helper.desktop")
payload("CH_EMBED_UNINSTALL", "uninstall.sh")
PY
}

test_generator_is_current() {
  local tmp
  tmp=$(mktemp -d)
  cp "${ROOT}/install.sh" "${tmp}/install.sh"
  cp "${ROOT}/command-helper-installer.sh" "${tmp}/command-helper-installer.sh"
  bash "${ROOT}/scripts/build-installer.sh" >/dev/null
  diff -u "${tmp}/install.sh" "${ROOT}/install.sh"
  diff -u "${tmp}/command-helper-installer.sh" "${ROOT}/command-helper-installer.sh"
  bash "${ROOT}/scripts/build-installer.sh" >/dev/null
  diff -u "${tmp}/install.sh" "${ROOT}/install.sh"
  rm -rf "$tmp"
}

test_no_personal_strings() {
  python3 - "$ROOT" << 'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
pattern = re.compile("ani" "me" + "|" + "68" "00" + "|" + "50" "80" + "|" + "/hom" + "e/")
bad = []
for path in root.rglob("*"):
    if not path.is_file():
        continue
    if ".git" in path.parts:
        continue
    data = path.read_bytes()
    if b"\0" in data:
        continue
    if pattern.search(data.decode("utf-8", "ignore")):
        bad.append(str(path))
if bad:
    print("Found personal or machine-specific strings in:", file=sys.stderr)
    print("\n".join(bad), file=sys.stderr)
    raise SystemExit(1)
PY
}

test_arch
test_sha256
test_download_verified
test_classes
test_bad_model_is_removed
test_required_bytes_without_downloads
test_desktop_render
test_desktop_dir_from_user_dirs
test_repo_desktop_uses_path_lookup
test_path_snippet_once
test_install_scripts_only
test_uninstall
test_help_and_version
test_payloads_match_sources
test_generator_is_current
test_no_personal_strings

printf 'installer tests passed\n'
