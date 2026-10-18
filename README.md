# Command Helper

Command Helper turns a plain-English request into one Linux command. It runs a small language model on your computer, shows you the command, and waits for you to say whether to run it.

```text
$ ask show me my disk space

Command:     df -h
Explanation: Shows how much disk space is used and free on each drive.
(2.4s)
Run it? [y/N] y
------------------------------------------------------------
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda2        50G   20G   30G  40% /
------------------------------------------------------------
Done.
```

Your question stays on this computer. There is no account, no API key, and no cloud service. A graphics card is not required.

## What it handles well

Everyday tasks work well: listing files, checking disk space, finding a file, looking at a process, or a short chain of commands joined with `&&`.

It can get a long or unusual task wrong. Read the command before you run it.

It does not remember earlier requests. Each question stands on its own.

It does not check whether a command worked. That is why it always shows the command and asks you before running anything.

## What you need

- A Linux computer. Ubuntu, Debian, Fedora, Arch, and most other distributions work.
- A reasonably modern CPU, roughly from the last 8–10 years. The model runs on the CPU.
- About 8 GB of memory is recommended. The installer warns when there is less, and it stops when there is not enough to load the model (about 4 GB).
- About 3 GB of free disk space. The installer checks for 3.5 GB free before it downloads the model.
- No graphics card.
- Answers usually take a few seconds. The first answer after a quiet period takes a little longer while the model loads.

Python 3, `curl`, and `tar` are used. They are already installed on a normal desktop.

## Install

Pick one of the two ways below. Both install Command Helper for your user only, under `~/.local`. Neither one asks for sudo. Both are safe to run again: if a download is already there and the checksum matches, it is skipped.

The installer downloads two pinned files and checks SHA256 checksums before it keeps them:

| Piece | What it is | SHA256 |
| --- | --- | --- |
| llama.cpp `b11716` CPU build | runs the model, about 18 MB | x86_64 `8c08b19bee40d118b803d58fd8f6633ba311ce3c7f1f0138262e636f02aa11f0` |
| same release, arm64 CPU build | used on arm64 computers | `8cbdc3e5df1e7f37de5c1be4ef93dd4fadea9e0b958f92af6f9c4c84c9882519` |
| `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` | the model, 2497281120 bytes (about 2.5 GB) | `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597` |

The model URL is pinned to Hugging Face commit `a06e946bb6b655725eafa393f4a9745d460374c9` of `unsloth/Qwen3-4B-Instruct-2507-GGUF`.

### One file

This is the easy way. The script contains the program and then downloads llama.cpp and the model.

Download it and read it first. It is a text file. You should see the checksums above near the top, and you should see that it never calls sudo.

```bash
curl -fsSL -o command-helper-installer.sh \
  https://raw.githubusercontent.com/cartrette88/New-User-Linux-Helper-/main/command-helper-installer.sh
less command-helper-installer.sh
bash command-helper-installer.sh
```

After a release is published, the same file is attached to that release. For version 1.0.0 the address is:

```bash
curl -fsSL -o command-helper-installer.sh \
  https://github.com/cartrette88/New-User-Linux-Helper-/releases/download/v1.0.0/command-helper-installer.sh
less command-helper-installer.sh
bash command-helper-installer.sh
```

A one-line install also works. Use it only after you trust the script, because piping a download straight into the shell runs it immediately:

```bash
curl -fsSL https://raw.githubusercontent.com/cartrette88/New-User-Linux-Helper-/main/command-helper-installer.sh | bash
```

### Project files

Clone the project, or download the files and keep this layout:

```text
install.sh
uninstall.sh
bin/ask
bin/command-helper-launch
share/command-helper.desktop
```

Then, from the folder that contains `install.sh`:

```bash
git clone https://github.com/cartrette88/New-User-Linux-Helper-.git
cd New-User-Linux-Helper-
./install.sh
```

`install.sh` copies the program into `~/.local` and downloads the same pinned llama.cpp build and model as the one-file installer.

The file `share/command-helper.desktop` looks up `command-helper-launch` on `PATH`. During install, that line is rewritten to the real path on your computer, for both the app menu and the desktop icon.

## How to use it

Open a new terminal after installing, so it can find `ask`. Then:

```bash
ask show me my disk space
ask list the files in my home folder
ask
```

`ask` on its own opens a prompt:

```text
ask>
```

Type a request and press Enter. Type `quit` (or press Ctrl+D) to leave.

`ask --print list my files` shows a command and does not offer to run it.

`ask --help` prints a short usage note. `ask --version` prints the version.

You can also open **Command Helper** from the app menu. A terminal window opens with the `ask>` prompt. If you have a Desktop folder, an icon is placed there too.

The first question loads the model, so it takes a few extra seconds. Later questions are usually a few seconds. After 15 minutes with no questions, the model unloads to free memory. The next question loads it again.

## Safety

Command Helper never runs a command until you answer.

For an ordinary command it asks:

```text
Run it? [y/N]
```

`y` or `yes` runs it. Pressing Enter, or typing anything else, leaves it unrun.

If the command can delete or change things, or it needs administrator rights, you get a red warning. Moving files, deleting files, formatting a disk, shutting down, stopping a program, and downloading a script to run it are in that group. Package removal on apt, dnf, yum, zypper, snap, and pacman is in that group too. You then have to type `yes` in full. `y` is not enough.

```text
 WARNING: this command can change or delete things, or needs root
  - uses sudo (runs as administrator/root)
Read it carefully. If you are not sure, do NOT run it.
Type 'yes' in full to run it, anything else cancels:
```

The warning is a guardrail. It can miss a harmful command, and it can flag a command you consider harmless. Read the command either way. If you are unsure, leave it unrun.

When a command needs your password, `sudo` asks for it in the terminal. Command Helper never sees that password and does not store it.

## Privacy

- The model server listens only on `127.0.0.1` (this computer). Other computers cannot connect to it.
- There is no API key and no account.
- Questions are not saved. Arrow-key history lasts only until you close the terminal.
- Nothing is sent to a telemetry service.
- The installer does contact GitHub and Hugging Face, once, to download llama.cpp and the model. After that, asking questions stays on this computer.

## Optional: NVIDIA graphics card

The installer always sets up the CPU build, including when it notices an NVIDIA card. That build works on every supported computer.

To use an NVIDIA card instead, you need a working driver (`nvidia-smi` should print the card) and the matching CUDA build of the same llama.cpp release. These steps are for a 64-bit PC. arm64 CUDA builds are listed on the same release page.

```bash
curl -fL -o /tmp/llama-cuda.tar.gz \
  https://github.com/ggml-org/llama.cpp/releases/download/b11716/llama-b11716-bin-ubuntu-cuda-12.8-x64.tar.gz
echo "f467d630fd94d0bcf2a51269f0ecb6dd84125be620daca6497340a93373b2e69  /tmp/llama-cuda.tar.gz" | sha256sum -c -

curl -fL -o /tmp/llama-cudart.tar.gz \
  https://github.com/ggml-org/llama.cpp/releases/download/b11716/cudart-llama-b11716-bin-ubuntu-cuda-12.8-x64.tar.gz
echo "93138d385a12272383bb51bbc7bbe03b6f718136737a500c0c8b4db54cb18d24  /tmp/llama-cudart.tar.gz" | sha256sum -c -

rm -rf ~/.local/opt/llama.cpp/llama-b11716
mkdir -p ~/.local/opt/llama.cpp /tmp/llama-cudart
tar -xzf /tmp/llama-cuda.tar.gz -C ~/.local/opt/llama.cpp
tar -xzf /tmp/llama-cudart.tar.gz -C /tmp/llama-cudart
cp /tmp/llama-cudart/cudart-llama-b11716-bin-ubuntu-cuda-12.8-x64/*.so* \
  ~/.local/opt/llama.cpp/llama-b11716/

mkdir -p ~/.config/command-helper
printf 'cuda\n' > ~/.config/command-helper/backend

pkill -u "$USER" -f "llama-b11716/llama-server" || true
```

The next `ask` loads the model on the NVIDIA card. The server still listens only on `127.0.0.1`.

To go back to the CPU, delete `~/.config/command-helper/backend` and run the installer again. It sees that the CPU checksum is gone and puts the CPU build back.

## Uninstall

Either of these removes Command Helper for your user, including the model (about 2.5 GB) and llama.cpp:

```bash
command-helper-uninstall
```

```bash
./uninstall.sh
```

It does not use sudo. Running it again after it has finished is safe. It also removes the PATH lines it added to your shell startup files. Lines you wrote yourself stay put.

## Troubleshooting

**`ask: command not found`**
Open a new terminal. The installer adds `~/.local/bin` to PATH for bash and zsh. If you use fish, add that folder to the fish path yourself. In the current terminal you can run:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

**The installer says a program is missing**
Install that program with your software manager, then run the installer again. Typical names are `curl`, `python3`, and `tar`.

**The installer says the checksum did not match**
The download was thrown away. Run the installer again. A second failure usually means the network connection dropped.

**The installer says there is not enough disk space or memory**
Free some disk space, or use a computer with more memory. About 8 GB of memory and 3.5 GB of free disk space is the comfortable target.

**"The local model did not start"**
Read `~/.local/state/command-helper/llama-server.log`. Then run `ask` again. If the log says a library is missing, the llama.cpp download may be incomplete: run the installer again.

**The desktop icon does nothing**
Open Command Helper from the app menu, or run `ask` in a terminal. Some desktops ignore icons until you trust them. The app menu entry is the reliable one.

**The command looks wrong**
Leave it unrun and phrase the request again. `ask --print` is useful when you only want to look.

**The first question is slow, or a question after a break is slow**
The model is loading into memory. That is expected.

## Credits

- [llama.cpp](https://github.com/ggml-org/llama.cpp) runs the model. It is released under the MIT license. Command Helper pins release `b11716`.
- [Qwen3](https://github.com/QwenLM/Qwen3) is the language model, from Alibaba Cloud, under the Apache License 2.0. The weights used here are [Qwen3-4B-Instruct-2507](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507).
- The GGUF file is [unsloth/Qwen3-4B-Instruct-2507-GGUF](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF), file `Qwen3-4B-Instruct-2507-Q4_K_M.gguf`, also under the Apache License 2.0.

Command Helper itself is MIT. See [LICENSE](LICENSE). The installer downloads llama.cpp and the model; it does not redistribute those files.

## Project layout

| Path | Role |
| --- | --- |
| `bin/ask` | The program you run |
| `bin/command-helper-launch` | Opens a terminal running `ask` |
| `share/command-helper.desktop` | App-menu entry. The installer fills in the path |
| `install.sh` | Installs the files above and downloads llama.cpp and the model |
| `uninstall.sh` | Removes the install |
| `command-helper-installer.sh` | The same install, as one file |
| `scripts/common.sh` | Shared install logic |
| `scripts/build-installer.sh` | Rebuilds `install.sh` and `command-helper-installer.sh` |
| `tests/` | Checks for the danger detector and the installer |

`install.sh` and `command-helper-installer.sh` are generated. After changing `bin/ask`, the launcher, the desktop file, `uninstall.sh`, or `scripts/common.sh`, run:

```bash
bash scripts/build-installer.sh
```
