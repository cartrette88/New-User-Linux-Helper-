#!/usr/bin/env bash
# Command Helper installer.
# Installs for the current user only. Does not use sudo.
# SPDX-License-Identifier: MIT
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this installer with bash:  bash install.sh" >&2
  exit 1
fi
set -euo pipefail

VERSION="1.0.0"

# Pinned downloads. The single-file installer copies these lines into its header.
LLAMA_VERSION="b11716"
# Also printed by --help. The single-file installer header reads this line.
LLAMA_COMMIT="797de63b2"
LLAMA_REPO="ggml-org/llama.cpp"
SHA_CPU_X64="8c08b19bee40d118b803d58fd8f6633ba311ce3c7f1f0138262e636f02aa11f0"
SHA_CPU_ARM64="8cbdc3e5df1e7f37de5c1be4ef93dd4fadea9e0b958f92af6f9c4c84c9882519"
SHA_CUDA_X64="f467d630fd94d0bcf2a51269f0ecb6dd84125be620daca6497340a93373b2e69"
SHA_CUDART_X64="93138d385a12272383bb51bbc7bbe03b6f718136737a500c0c8b4db54cb18d24"

MODEL_REPO="unsloth/Qwen3-4B-Instruct-2507-GGUF"
MODEL_REVISION="a06e946bb6b655725eafa393f4a9745d460374c9"
MODEL_FILE="Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
MODEL_SHA256="3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597"
MODEL_BYTES=2497281120
MODEL_URL="https://huggingface.co/${MODEL_REPO}/resolve/${MODEL_REVISION}/${MODEL_FILE}"

# 3.5 GiB for the CPU install. 5 GiB when --cuda also fetches the runtime libraries.
MIN_FREE_KB=$((35 * 1024 * 1024 / 10))
MIN_FREE_CUDA_KB=$((5 * 1024 * 1024))

PATH_BEGIN='# BEGIN command-helper PATH (added by the installer)'
PATH_END='# END command-helper PATH'
# The PATH snippet is stored literally. The user's shell expands it later.
# shellcheck disable=SC2016
PATH_BLOCK='# BEGIN command-helper PATH (added by the installer)
case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) PATH="${HOME}/.local/bin:${PATH}" ;;
esac
export PATH
# END command-helper PATH'

BACKEND="cpu"
ARCH=""
MODEL_IS_READY=0
EXPECTED_LLAMA_SHA=""
HARD_PROBLEMS=()
SOFT_PROBLEMS=()
TMP_DIRS=()
BIN_DIR=""
LLAMA_PARENT=""
LLAMA_DIR=""
SHARE_DIR=""
MODEL_DIR=""
MODEL_PATH=""
APPS_DIR=""
CACHE_DIR=""

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

say() { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
detail() { printf '    %s\n' "$*"; }

die() {
  printf '\nError: %s\n' "$1" >&2
  shift || true
  local line
  for line in "$@"; do
    printf '       %s\n' "$line" >&2
  done
  exit 1
}

gb_from_kb() {
  awk -v k="$1" 'BEGIN { printf "%.1f", k / 1024 / 1024 }'
}

cleanup() {
  local d
  if ((${#TMP_DIRS[@]})); then
    for d in "${TMP_DIRS[@]}"; do
      rm -rf -- "$d"
    done
  fi
}

usage() {
  cat <<EOF
Usage: bash install.sh [--check] [--cuda]

Install Command Helper for the current user. This does not use sudo.

Options:
  --check    Look at this computer and stop. Do not download or install.
  --cuda     Optional NVIDIA build for 64-bit Intel/AMD. CPU is the default.
  --help     Show this message.
  --version  Show the installer version.

The installer is safe to run again. Files that already match are skipped.
llama.cpp build: ${LLAMA_VERSION} (${LLAMA_COMMIT})

To ignore the memory and disk limits (the model may then fail to start):
  COMMAND_HELPER_FORCE=1 bash install.sh
EOF
}

set_paths() {
  BIN_DIR="${HOME}/.local/bin"
  LLAMA_PARENT="${HOME}/.local/opt/llama.cpp"
  LLAMA_DIR="${LLAMA_PARENT}/llama-${LLAMA_VERSION}"
  SHARE_DIR="${HOME}/.local/share/command-helper"
  MODEL_DIR="${SHARE_DIR}/models"
  MODEL_PATH="${MODEL_DIR}/${MODEL_FILE}"
  APPS_DIR="${HOME}/.local/share/applications"
  CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/command-helper"
}

hard() { HARD_PROBLEMS+=("$1"); }
soft() { SOFT_PROBLEMS+=("$1"); }

hash_ok() {
  local file=$1 expected=$2 got
  [[ -f $file ]] || return 1
  got=$(sha256sum -- "$file" | awk '{print $1}')
  [[ $got == "$expected" ]]
}

report_problems() {
  local p
  if ((${#HARD_PROBLEMS[@]})); then
    say ""
    say "Fix these first:"
    for p in "${HARD_PROBLEMS[@]}"; do
      say "  - ${p}"
    done
  fi
  if ((${#SOFT_PROBLEMS[@]})); then
    say ""
    say "This computer is below the suggested size:"
    for p in "${SOFT_PROBLEMS[@]}"; do
      say "  - ${p}"
    done
    if [[ ${COMMAND_HELPER_FORCE:-} != 1 ]]; then
      say "To install anyway (the model may not start):"
      say "  COMMAND_HELPER_FORCE=1 bash install.sh"
    fi
  fi
  if ((${#HARD_PROBLEMS[@]})); then
    return 1
  fi
  if ((${#SOFT_PROBLEMS[@]})) && [[ ${COMMAND_HELPER_FORCE:-} != 1 ]]; then
    return 1
  fi
  return 0
}

require_layout() {
  local rel missing=0
  for rel in bin/ask bin/command-helper-launch share/command-helper.desktop uninstall.sh; do
    if [[ ! -f ${SCRIPT_DIR}/${rel} ]]; then
      hard "Missing ${rel} beside this installer."
      missing=1
    fi
  done
  if [[ $missing -eq 1 ]]; then
    hard "Keep the project folders, or run command-helper-installer.sh (the single-file installer)."
  fi
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

preflight() {
  local mem_kb avail_kb free_kb need_kb need_label mem_gb free_gb
  HARD_PROBLEMS=()
  SOFT_PROBLEMS=()
  MODEL_IS_READY=0
  set_paths

  step "Checking this computer"

  if [[ $(uname -s) != Linux ]]; then
    hard "This installer is for Linux. This system is $(uname -s)."
  else
    detail "System: Linux"
  fi

  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    hard "Run this as your normal user, without sudo."
  fi

  case $(uname -m) in
    x86_64|amd64)
      ARCH="x64"
      detail "Processor: 64-bit Intel/AMD"
      ;;
    aarch64|arm64)
      ARCH="arm64"
      detail "Processor: 64-bit ARM"
      ;;
    *)
      ARCH=""
      hard "This installer supports 64-bit Intel/AMD and 64-bit ARM. This computer reports $(uname -m)."
      ;;
  esac

  if [[ $BACKEND == cuda ]]; then
    if [[ $ARCH != x64 ]]; then
      hard "The optional NVIDIA install is only for 64-bit Intel/AMD. Run the installer without --cuda."
    else
      detail "Install type: NVIDIA CUDA 12.8 (optional)"
    fi
  else
    detail "Install type: CPU (no graphics card)"
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    hard "Python 3 is required. Install python3 from your distribution, then run this again."
  elif ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 6) else 1)'; then
    hard "Python 3.6 or newer is required. This python3 is older than that."
  else
    detail "Python 3: found"
  fi

  local cmd
  for cmd in tar sha256sum awk mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      hard "The command '${cmd}' is required and was not found."
    fi
  done
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    hard "Install curl or wget, then run this again. One of them is needed to download the model."
  fi

  if [[ ! -w $HOME ]]; then
    hard "The home folder is not writable, so the installer cannot put files there."
  fi

  require_layout

  if [[ -f $MODEL_PATH ]]; then
    detail "A model file is already here. Checking its fingerprint..."
    if hash_ok "$MODEL_PATH" "$MODEL_SHA256"; then
      MODEL_IS_READY=1
      detail "The model fingerprint matches."
    else
      detail "The model file does not match the pinned fingerprint."
    fi
  else
    detail "The model is not installed yet."
  fi

  if [[ -r /proc/meminfo ]]; then
    mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    if [[ ! ${mem_kb:-} =~ ^[0-9]+$ ]]; then
      hard "Could not read the memory size from this computer."
    else
      mem_gb=$(gb_from_kb "$mem_kb")
      if (( mem_kb < 6 * 1024 * 1024 )); then
        soft "This computer has ${mem_gb} GB of memory. About 8 GB is recommended, and less than 6 GB is too small for this model."
      elif (( mem_kb < 8 * 1024 * 1024 )); then
        detail "Memory: ${mem_gb} GB. About 8 GB is recommended, so answers may be slow."
      else
        detail "Memory: ${mem_gb} GB"
      fi
      avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
      if [[ ${avail_kb:-} =~ ^[0-9]+$ ]] && (( avail_kb < 4 * 1024 * 1024 )); then
        detail "Only about $(gb_from_kb "$avail_kb") GB is free right now. Close other programs if the model does not start."
      fi
    fi
  else
    hard "Could not read memory information from this computer."
  fi

  need_kb=$MIN_FREE_KB
  need_label="3.5"
  if [[ $BACKEND == cuda ]]; then
    need_kb=$MIN_FREE_CUDA_KB
    need_label="5"
  fi
  if [[ $MODEL_IS_READY -eq 1 ]]; then
    local model_kb=$((MODEL_BYTES / 1024))
    local floor_kb=$((512 * 1024))
    if (( need_kb > model_kb )); then
      need_kb=$((need_kb - model_kb))
    else
      need_kb=0
    fi
    if (( need_kb < floor_kb )); then
      need_kb=$floor_kb
    fi
  fi

  free_kb=$(df -Pk "$HOME" | awk 'NR==2 {print $4}')
  if [[ ! ${free_kb:-} =~ ^[0-9]+$ ]]; then
    hard "Could not read free disk space for the home folder."
  else
    free_gb=$(gb_from_kb "$free_kb")
    detail "Free disk space: ${free_gb} GB (about ${need_label} GB needed)"
    if (( free_kb < need_kb )); then
      soft "About ${need_label} GB of free disk space is needed. This folder has ${free_gb} GB free."
    fi
  fi

  report_problems
}

download_file() {
  local url=$1 dest=$2
  if command -v curl >/dev/null 2>&1; then
    local -a curl_opts=(-fL --proto '=https' --retry 5 --retry-delay 2 --connect-timeout 30)
    if [[ -t 2 ]]; then
      curl_opts+=(--progress-bar)
    else
      curl_opts+=(-sS)
    fi
    if [[ -f $dest ]]; then
      curl "${curl_opts[@]}" -C - -o "$dest" "$url"
    else
      curl "${curl_opts[@]}" -o "$dest" "$url"
    fi
  elif command -v wget >/dev/null 2>&1; then
    local -a wget_opts=(-t 5 --connect-timeout=30 -c -O "$dest")
    if [[ ! -t 2 ]]; then
      wget_opts=(-q "${wget_opts[@]}")
    fi
    wget "${wget_opts[@]}" "$url"
  else
    die "This installer needs curl or wget to download files."
  fi
}

fetch_verified() {
  local url=$1 dest=$2 expected=$3 label=$4 attempt
  mkdir -p "$(dirname "$dest")"
  for attempt in 1 2; do
    if [[ -f $dest ]] && hash_ok "$dest" "$expected"; then
      detail "Already here, and the fingerprint matches."
      return 0
    fi
    if [[ $attempt -eq 2 && -f $dest ]]; then
      rm -f -- "$dest"
    fi
    if [[ $attempt -eq 1 ]]; then
      detail "Downloading ${label}..."
    else
      detail "Downloading ${label} again from the start..."
    fi
    if ! download_file "$url" "$dest"; then
      detail "The download stopped before it finished."
      rm -f -- "$dest"
      if [[ $attempt -eq 2 ]]; then
        die "Could not download ${label}." \
          "URL: ${url}" \
          "Check the internet connection and run the installer again."
      fi
      continue
    fi
    detail "Checking the fingerprint..."
    if hash_ok "$dest" "$expected"; then
      detail "Fingerprint matches."
      return 0
    fi
    detail "The fingerprint did not match, so that download was deleted."
    rm -f -- "$dest"
  done
  die "The download for ${label} did not match the pinned fingerprint." \
    "URL: ${url}" \
    "Run the installer again for a fresh copy."
}

llama_stamp_ok() {
  [[ -n $EXPECTED_LLAMA_SHA ]] || return 1
  [[ -x ${LLAMA_DIR}/llama-server ]] || return 1
  [[ -f ${LLAMA_DIR}/.command-helper-stamp ]] || return 1
  grep -qx "backend=${BACKEND}" "${LLAMA_DIR}/.command-helper-stamp" || return 1
  grep -qx "llama_sha256=${EXPECTED_LLAMA_SHA}" "${LLAMA_DIR}/.command-helper-stamp" || return 1
  if [[ $BACKEND == cuda ]]; then
    grep -qx "cudart_sha256=${SHA_CUDART_X64}" "${LLAMA_DIR}/.command-helper-stamp" || return 1
    [[ -f ${LLAMA_DIR}/libcudart.so.12 ]] || return 1
    [[ -f ${LLAMA_DIR}/libcublas.so.12 ]] || return 1
    [[ -f ${LLAMA_DIR}/libcublasLt.so.12 ]] || return 1
  fi
  return 0
}

write_stamp() {
  local backend=$1 llama_sha=$2 cudart_sha=$3
  cat > "${LLAMA_DIR}/.command-helper-stamp" <<EOF
backend=${backend}
llama_sha256=${llama_sha}
cudart_sha256=${cudart_sha}
EOF
}

guard_llama_dir() {
  case $LLAMA_DIR in
    "${HOME}/.local/opt/llama.cpp/llama-${LLAMA_VERSION}") ;;
    *) die "Refusing to replace an unexpected llama.cpp folder." ;;
  esac
}

unpack_llama() {
  local tarball=$1 tmp
  tmp=$(mktemp -d)
  TMP_DIRS+=("$tmp")
  tar -xzf "$tarball" -C "$tmp"
  if [[ -L ${tmp}/llama-${LLAMA_VERSION} || ! -d ${tmp}/llama-${LLAMA_VERSION} ]]; then
    die "The llama.cpp archive did not have the expected folder."
  fi
  if [[ ! -x ${tmp}/llama-${LLAMA_VERSION}/llama-server ]]; then
    die "The llama.cpp archive did not contain llama-server."
  fi
  guard_llama_dir
  mkdir -p "$LLAMA_PARENT"
  rm -rf -- "$LLAMA_DIR"
  mv -- "${tmp}/llama-${LLAMA_VERSION}" "$LLAMA_DIR"
}

unpack_cudart() {
  local tarball=$1 tmp lib
  local -a libs=()
  tmp=$(mktemp -d)
  TMP_DIRS+=("$tmp")
  tar -xzf "$tarball" -C "$tmp"
  shopt -s nullglob
  libs=("${tmp}"/cudart-llama-*/lib*.so*)
  shopt -u nullglob
  if ((${#libs[@]} == 0)); then
    die "The CUDA runtime archive did not contain libraries."
  fi
  cp -f -- "${libs[@]}" "${LLAMA_DIR}/"
  for lib in libcudart.so.12 libcublas.so.12 libcublasLt.so.12; do
    if [[ ! -f ${LLAMA_DIR}/${lib} ]]; then
      die "Missing ${lib} after unpacking the CUDA runtime."
    fi
    chmod 755 "${LLAMA_DIR}/${lib}"
  done
}

install_engine() {
  local name sha url tarball cudart_name cudart_url cudart
  set_paths
  cudart=""
  if [[ $BACKEND == cuda ]]; then
    EXPECTED_LLAMA_SHA=$SHA_CUDA_X64
    name="llama-${LLAMA_VERSION}-bin-ubuntu-cuda-12.8-x64.tar.gz"
    sha=$SHA_CUDA_X64
  elif [[ $ARCH == arm64 ]]; then
    EXPECTED_LLAMA_SHA=$SHA_CPU_ARM64
    name="llama-${LLAMA_VERSION}-bin-ubuntu-arm64.tar.gz"
    sha=$SHA_CPU_ARM64
  else
    EXPECTED_LLAMA_SHA=$SHA_CPU_X64
    name="llama-${LLAMA_VERSION}-bin-ubuntu-x64.tar.gz"
    sha=$SHA_CPU_X64
  fi

  if llama_stamp_ok; then
    if [[ $BACKEND == cuda ]]; then
      step "llama.cpp ${LLAMA_VERSION} (NVIDIA CUDA) is already installed"
    else
      step "llama.cpp ${LLAMA_VERSION} (CPU) is already installed"
    fi
    detail "The fingerprint matches, so that download is skipped."
    return 0
  fi

  url="https://github.com/${LLAMA_REPO}/releases/download/${LLAMA_VERSION}/${name}"
  tarball="${CACHE_DIR}/${name}"
  if [[ $BACKEND == cuda ]]; then
    step "Downloading llama.cpp ${LLAMA_VERSION} for NVIDIA CUDA 12.8"
    detail "This optional build is for an NVIDIA graphics card. You still need an NVIDIA driver."
    detail "The matching CUDA runtime libraries are downloaded next."
  else
    step "Downloading llama.cpp ${LLAMA_VERSION} (CPU)"
    detail "This small program runs the language model on the processor."
  fi
  fetch_verified "$url" "$tarball" "$sha" "llama.cpp"

  if [[ $BACKEND == cuda ]]; then
    cudart_name="cudart-llama-${LLAMA_VERSION}-bin-ubuntu-cuda-12.8-x64.tar.gz"
    cudart_url="https://github.com/${LLAMA_REPO}/releases/download/${LLAMA_VERSION}/${cudart_name}"
    cudart="${CACHE_DIR}/${cudart_name}"
    fetch_verified "$cudart_url" "$cudart" "$SHA_CUDART_X64" "CUDA runtime libraries"
  fi

  detail "Unpacking llama.cpp..."
  unpack_llama "$tarball"
  if [[ $BACKEND == cuda ]]; then
    unpack_cudart "$cudart"
    write_stamp cuda "$sha" "$SHA_CUDART_X64"
  else
    write_stamp cpu "$sha" "-"
  fi
  detail "llama.cpp is installed."
}

install_model() {
  local partial
  set_paths
  step "Downloading the language model (about 2.5 GB)"
  detail "File: ${MODEL_FILE}"
  detail "It stays on this computer. If the download stops, run the installer again."
  if [[ $MODEL_IS_READY -eq 1 ]]; then
    detail "The model is already installed and the fingerprint matches."
    return 0
  fi
  if [[ -f $MODEL_PATH ]]; then
    detail "Removing a model file that did not match the fingerprint."
    rm -f -- "$MODEL_PATH"
  fi
  mkdir -p "$MODEL_DIR"
  partial="${MODEL_PATH}.partial"
  fetch_verified "$MODEL_URL" "$partial" "$MODEL_SHA256" "language model"
  mv -f -- "$partial" "$MODEL_PATH"
  chmod 644 "$MODEL_PATH"
  detail "Model installed."
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

write_path_block() {
  local file=$1 tmp
  [[ -e $file ]] || : > "$file"
  strip_path_block "$file"
  tmp=$(mktemp)
  if [[ -s $file ]]; then
    cat -- "$file" > "$tmp"
    printf '\n' >> "$tmp"
  fi
  printf '%s\n' "$PATH_BLOCK" >> "$tmp"
  chmod --reference="$file" "$tmp" 2>/dev/null || chmod 644 "$tmp"
  mv -f -- "$tmp" "$file"
}

refresh_user_path() {
  local file
  set_paths
  for file in "${HOME}/.bashrc" "${HOME}/.profile"; do
    write_path_block "$file"
  done
  if [[ -f ${HOME}/.zshrc ]]; then
    write_path_block "${HOME}/.zshrc"
  fi
}

write_desktop() {
  local dest=$1 mode=$2 template exec_path exec_value
  template=$(<"${SCRIPT_DIR}/share/command-helper.desktop")
  exec_path="${BIN_DIR}/command-helper-launch"
  if [[ $template != *"@EXEC@"* ]]; then
    die "The desktop file is missing @EXEC@."
  fi
  if [[ $exec_path == *[[:space:]]* ]]; then
    exec_value="\"${exec_path}\""
  else
    exec_value=$exec_path
  fi
  printf '%s\n' "${template//@EXEC@/${exec_value}}" > "$dest"
  chmod "$mode" "$dest"
}

install_user_files() {
  local desk=""
  set_paths
  step "Installing Command Helper"
  mkdir -p "$BIN_DIR" "$APPS_DIR" "$SHARE_DIR"
  cp -f -- "${SCRIPT_DIR}/bin/ask" "${BIN_DIR}/ask"
  cp -f -- "${SCRIPT_DIR}/bin/command-helper-launch" "${BIN_DIR}/command-helper-launch"
  cp -f -- "${SCRIPT_DIR}/uninstall.sh" "${BIN_DIR}/command-helper-uninstall"
  chmod 755 "${BIN_DIR}/ask" "${BIN_DIR}/command-helper-launch" "${BIN_DIR}/command-helper-uninstall"
  write_desktop "${APPS_DIR}/command-helper.desktop" 644
  detail "App menu entry: Command Helper"
  if desk=$(desktop_dir); then
    write_desktop "${desk}/command-helper.desktop" 755
    if command -v gio >/dev/null 2>&1; then
      gio set "${desk}/command-helper.desktop" metadata::trusted true >/dev/null 2>&1 || true
    fi
    detail "Desktop icon added."
  else
    detail "No Desktop folder was found, so no desktop icon was added."
    detail "Command Helper is still in the app menu, and the ask command still works."
  fi
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
  fi
  refresh_user_path
  detail "New terminal windows can find the ask command."
}

say_done() {
  step "Installed"
  say "Command Helper is installed for your user only."
  say ""
  say "Open a new Terminal window and type:"
  say ""
  say "    ask show me my disk space"
  say ""
  say "Or open Command Helper from the app menu."
  say "The first answer takes a few extra seconds while the model loads."
  say "If a terminal says the ask command was not found, close it and open a new one."
  say ""
  say "Remove it later with:  command-helper-uninstall"
  if [[ $BACKEND == cuda ]]; then
    say ""
    say "The NVIDIA files are installed. To use the graphics card, type:"
    say ""
    say "    COMMAND_HELPER_BACKEND=cuda ask show me my disk space"
    say ""
    say "A normal ask command stays on the processor."
  fi
}

main() {
  local check_only=0
  BACKEND="cpu"
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help) usage; exit 0 ;;
      --version) printf '%s\n' "$VERSION"; exit 0 ;;
      --check) check_only=1; shift ;;
      --cuda) BACKEND="cuda"; shift ;;
      *) die "Unknown option: $1" "Try: bash install.sh --help" ;;
    esac
  done

  umask 022
  TMP_DIRS=()
  trap cleanup EXIT
  set_paths

  if [[ $check_only -eq 1 ]]; then
    say "Checking this computer. Nothing will be downloaded or installed."
  else
    say "Command Helper installer ${VERSION}"
    say "This installs a local command helper for your user only."
    say "It does not use sudo, and it does not send what you type anywhere."
  fi

  if ! preflight; then
    exit 1
  fi
  if [[ $check_only -eq 1 ]]; then
    say ""
    say "This computer looks ready for Command Helper."
    exit 0
  fi

  install_engine
  install_model
  install_user_files
  say_done
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
