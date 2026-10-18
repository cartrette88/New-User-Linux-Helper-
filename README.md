# Command Helper

Command Helper turns a plain-English sentence into one Linux command, on your own computer.

You type something like `ask show me my disk space`. A small local language model suggests one command and explains it in one sentence. It shows you the command and asks `Run it? [y/N]`. Nothing runs until you say so.

If you want it running soon, use the single-file installer in [Install it](#install-it). If you have never used Linux, read [New to Linux?](#new-to-linux) first.

## An example

```text
$ ask show me my disk space

Command:     df -h
Explanation: Shows how much disk space is used and free.
(2.4s)
Run it? [y/N] y
------------------------------------------------------------
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       200G   40G  160G  20% /
------------------------------------------------------------
Done.
```

Press Enter alone at `Run it? [y/N]` and the command is not run. The letter `y` runs ordinary commands. A command that can delete things, or that needs administrator rights, gets a red warning instead, and you have to type `yes` in full.

## New to Linux?

The Terminal is a window where you type instructions. On Windows this was Command Prompt or PowerShell.

On Ubuntu and many similar desktops:

1. Press the key with the Windows logo. Linux calls it the Super key.
2. Type `Terminal`.
3. Press Enter.

The shortcut Ctrl+Alt+T opens the Terminal on Ubuntu and several other desktops.

A window opens with a blinking cursor. That is where you type `ask`, then press Enter. You can also open **Command Helper** from the app menu (the same place you open other programs, like the Windows Start menu) after installing.

## What it is good at, and what it gets wrong

It is good at everyday tasks and short jobs that are one command, or a few commands joined with `&&` (run the next one only if the previous one worked). Examples: disk space, listing files, finding a large folder, creating a folder, updating software.

It can get long or unusual tasks wrong. Read the command before you run it.

It does not remember earlier requests. Each question stands on its own.

It does not check whether a command worked. It will run the command you accepted and show the exit code, but it does not read the output or try a different command if something failed. That is why it always asks you first.

The suggestions lean toward common Ubuntu commands. On another distribution, skip a suggestion that names a tool you do not have.

## What you need

- No graphics card. The normal install uses the processor only.
- About 8 GB of memory (RAM) recommended. The installer stops below about 6 GB unless you override it.
- About 3 GB of disk space for the model. The installer looks for about 3.5 GB free.
- Most Linux distributions, with Python 3 (already installed on most of them).
- A reasonably modern 64-bit processor: Intel, AMD, or ARM.
- Answers in a few seconds once the model is loaded. The first question, and the first question after about 15 minutes of idle time, takes a few extra seconds while the model loads.

The first install needs the internet. After that, Command Helper works offline.

## Install it

Both ways install the same thing, for your user only. They do not use `sudo` (the administrator password). They are safe to run again: finished downloads are skipped.

What gets installed:

- `~/.local/bin/ask` — the command you type
- `~/.local/bin/command-helper-launch` — opens a Terminal with the helper
- `~/.local/bin/command-helper-uninstall` — removes it
- an app-menu entry named Command Helper
- a desktop icon, when you have a Desktop folder
- llama.cpp, the program that runs the model, under `~/.local/opt/llama.cpp/llama-b11716/`
- the model under `~/.local/share/command-helper/models/`
- a few lines in `~/.bashrc` and `~/.profile` so new terminals can find `ask`

The model listens only on this computer, at `127.0.0.1` port `8742`. It is not a program that starts at boot. `ask` starts it when you need it, and it unloads after about 15 minutes of idle time.

### Single file (easiest)

Download the installer, read it, then run it:

```bash
curl -fsSL -o command-helper-installer.sh https://raw.githubusercontent.com/cartrette88/New-User-Linux-Helper-/main/command-helper-installer.sh
bash command-helper-installer.sh
```

Open `command-helper-installer.sh` in any text editor before you run it. The program files are written out in plain text inside that file, with the pinned download fingerprints at the top.

After a numbered release exists, the same file is attached to the GitHub Release. You can download that copy instead:

```bash
curl -fsSL -o command-helper-installer.sh https://github.com/cartrette88/New-User-Linux-Helper-/releases/latest/download/command-helper-installer.sh
bash command-helper-installer.sh
```

One-line install, only if you already trust this project. This runs the script immediately, which is why reading it first is the better option:

```bash
curl -fsSL https://raw.githubusercontent.com/cartrette88/New-User-Linux-Helper-/main/command-helper-installer.sh | bash
```

### Individual files

Download the project as a ZIP from the GitHub page (Code, then Download ZIP), unzip it, open a Terminal in that folder, and run:

```bash
bash install.sh
```

Or, if you already have git:

```bash
git clone https://github.com/cartrette88/New-User-Linux-Helper-.git
cd New-User-Linux-Helper-
bash install.sh
```

You can also download these files one at a time and keep the folders:

```text
bin/ask
bin/command-helper-launch
share/command-helper.desktop
install.sh
uninstall.sh
```

`bash install.sh` has to be run from the folder that contains `install.sh`, with `bin/` and `share/` beside it. That installer downloads the model and llama.cpp. The single-file installer already contains the program files and downloads the same model and llama.cpp.

`bash install.sh --check` looks at memory, disk space, and processor type, and does not download anything.

### Pinned versions

The installer checks a SHA256 fingerprint on every download. If the file does not match, it is deleted.

| Download | Fingerprint (SHA256) |
| --- | --- |
| llama.cpp b11716 CPU, 64-bit Intel/AMD (`797de63b2`) | `8c08b19bee40d118b803d58fd8f6633ba311ce3c7f1f0138262e636f02aa11f0` |
| llama.cpp b11716 CPU, 64-bit ARM | `8cbdc3e5df1e7f37de5c1be4ef93dd4fadea9e0b958f92af6f9c4c84c9882519` |
| llama.cpp b11716 CUDA 12.8, 64-bit Intel/AMD (only with `--cuda`) | `f467d630fd94d0bcf2a51269f0ecb6dd84125be620daca6497340a93373b2e69` |
| CUDA runtime libraries for that build (only with `--cuda`) | `93138d385a12272383bb51bbc7bbe03b6f718136737a500c0c8b4db54cb18d24` |
| `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` (Hugging Face revision `a06e946bb6b655725eafa393f4a9745d460374c9`) | `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597` |

llama.cpp comes from the official [b11716 release](https://github.com/ggml-org/llama.cpp/releases/tag/b11716). The model file comes from [unsloth/Qwen3-4B-Instruct-2507-GGUF](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF).

## Use it

One request:

```bash
ask show me my disk space
```

A prompt you can keep using (type `quit` to leave):

```bash
ask
```

Show a suggestion and never offer to run it:

```bash
ask --print how do I list the files in this folder
```

Help:

```bash
ask --help
```

In the `ask>` prompt, `quit`, `exit`, `q`, or `bye` leaves. Ctrl+D leaves. Ctrl+C cancels the question you are on.

## Why it asks before it runs anything

The model writes a command. You decide whether it runs.

- It always prints the command and a one-line explanation first.
- `Run it? [y/N]` — Enter means no. `y` means yes.
- If the command looks destructive or needs administrator rights, the warning is red. You must type `yes` in full. Any other answer cancels it.
- That warning covers deleting files (`rm` has no Recycle Bin), deleting folders, wiping or partitioning disks, changing ownership, recursive permission changes, removing software, shutting down or restarting, stopping programs, moving files, writing over files, scheduled-task deletion, and downloading a script and running it.
- The check is a list of patterns, not a perfect judge. A command can still be a bad idea without a red warning. Read it.
- If a command uses `sudo`, the system itself asks for your password. Command Helper never sees or stores that password. `sudo` is the Linux version of "Run as administrator."

## Privacy

The model runs on this computer. Nothing you type is sent to a cloud service, and nothing you type is saved.

There is no account, no API key, and no telemetry. The helper talks only to `127.0.0.1` (this computer, not the network).

The installer downloads llama.cpp from GitHub and the model from Hugging Face. Those are the downloads above. After they are on disk, answers do not need the internet.

## Uninstall

In a terminal:

```bash
command-helper-uninstall
```

Or, from a copy of this project:

```bash
bash uninstall.sh
```

It asks first. `y` removes Command Helper, the app-menu entry, the desktop icon, the model, the llama.cpp files it downloaded, and the PATH lines it added. Your documents stay. Pass `--yes` only when you already mean to remove it. This does not use sudo.

## Optional: NVIDIA graphics card

Skip this section if you do not have an NVIDIA card, or if you are not sure. The normal install is the one to use.

CPU is the default, including after a CUDA install. `ask` passes `--device none` and `-ngl 0`, and it hides CUDA, HIP, and ROCm devices, unless you opt in.

To download the official llama.cpp b11716 CUDA 12.8 build (64-bit Intel/AMD only) and the matching CUDA runtime libraries (`libcudart`, `libcublas`):

```bash
bash command-helper-installer.sh --cuda
```

or, from a checkout:

```bash
bash install.sh --cuda
```

That needs about 5 GB free. You still need an NVIDIA driver new enough for CUDA 12. The driver provides `libcuda`; the installer does not install a driver.

Use the graphics card for one run like this:

```bash
COMMAND_HELPER_BACKEND=cuda ask show me my disk space
```

A normal `ask` command stays on the processor. ARM computers stay on the CPU build. This installer does not set up AMD graphics cards.

## Troubleshooting

**The terminal says `ask` was not found.** Close that terminal and open a new one. The installer adds `~/.local/bin` for new terminals. If you use a shell other than bash and the command is still missing, add `~/.local/bin` to that shell's PATH. The desktop icon does not need this, because it uses the full path.

**The model did not start.** Read `~/.local/state/command-helper/llama-server.log`. Then run the installer again. It is safe to repeat, and it continues a stopped download.

**The download stopped halfway.** Run the same installer again.

**The computer is low on disk or memory.** Free some space, or close other programs. About 8 GB of memory and about 3.5 GB of free disk are the targets. Overriding the check is a last resort, and the model may not start:

```bash
COMMAND_HELPER_FORCE=1 bash install.sh
```

**The suggestion looks wrong.** Do not run it. Ask again in different words. Command Helper does not remember the previous question.

**The desktop icon does nothing.** Install a terminal program such as GNOME Terminal, Konsole, or Xfce Terminal, or open a terminal yourself and type `ask`.

**Something else is already using port 8742.** Command Helper will not start a second copy. Quit the other program using that port, or wait if a previous model server is still running. After about 15 minutes of idle time it unloads on its own.

**Python 3 is missing.** Install the `python3` package from your distribution, then run the installer again.

## Credits and license

Command Helper itself is MIT licensed. Copyright (c) 2026 cartrette88. See [LICENSE](LICENSE).

- [llama.cpp](https://github.com/ggml-org/llama.cpp) is MIT licensed. This project pins build b11716 (`797de63b2`).
- [Qwen3](https://github.com/QwenLM/Qwen3) is Apache-2.0 licensed. The model is Qwen3-4B-Instruct-2507.
- The GGUF file is [unsloth/Qwen3-4B-Instruct-2507-GGUF](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF), file `Qwen3-4B-Instruct-2507-Q4_K_M.gguf`.

## For maintainers

Pushing a tag named `v*` (for example `v1.0.0`) runs GitHub Actions. That publishes a GitHub Release and attaches `command-helper-installer.sh`.

First release, after this is on `main`:

```bash
git checkout main
git pull
git tag v1.0.0
git push origin v1.0.0
```

Open the Releases page and confirm the installer is attached. The workflow also prints the installer's SHA256 in the release notes.

After changing `install.sh`, `uninstall.sh`, `bin/ask`, `bin/command-helper-launch`, or `share/command-helper.desktop`, regenerate the single-file installer and commit it:

```bash
bash scripts/build-standalone-installer.sh
```

CI fails if the committed installer does not match those files.
