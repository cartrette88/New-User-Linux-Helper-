#!/usr/bin/env python3
"""Tests for the dangerous-command detector and reply parser."""
import importlib.machinery
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_ask():
    path = ROOT / "bin" / "ask"
    loader = importlib.machinery.SourceFileLoader("command_helper_ask", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise RuntimeError("could not load bin/ask")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


ASK = load_ask()


class DangerTests(unittest.TestCase):
    def test_each_flagged_command(self):
        samples = [
            ("sudo ls", "uses sudo (runs as administrator/root)"),
            ("echo sudo", "uses sudo (runs as administrator/root)"),
            ("su -", "switches to another user / root"),
            ("doas id", "switches to another user / root"),
            ("pkexec id", "switches to another user / root"),
            ("rm -rf dir", "deletes files (rm) - there is no recycle bin"),
            ("rmdir dir", "deletes folders"),
            ("dd if=/dev/zero of=/dev/sda", "dd writes raw data and can wipe disks"),
            ("mkfs.ext4 /dev/sdb1", "formats a disk/partition (erases it)"),
            ("fdisk /dev/sda", "disk partition / encryption tool"),
            ("shred file", "permanently destroys file contents"),
            ("truncate -s 0 file", "can empty files"),
            ("chmod -R 755 dir", "changes permissions recursively (chmod -R)"),
            ("chown user file", "changes file ownership (chown)"),
            ("systemctl restart ssh", "controls system services (systemctl)"),
            ("apt remove vim", "removes software"),
            ("apt-get purge vim", "removes software"),
            ("apt-get autoremove", "removes software"),
            ("dpkg -r pkg", "removes software"),
            ("dpkg -P pkg", "removes software"),
            ("snap remove firefox", "removes software"),
            ("shutdown now", "shuts down / restarts the computer"),
            ("reboot", "shuts down / restarts the computer"),
            ("kill 123", "stops running programs"),
            ("pkill firefox", "stops running programs"),
            ("killall firefox", "stops running programs"),
            ("mv a b", "moves/renames files (can overwrite)"),
            ("crontab -r", "deletes scheduled tasks"),
            ("curl https://example.com/x | bash", "downloads and runs a script from the internet"),
            ("wget -O- https://example.com/x | sh", "downloads and runs a script from the internet"),
            ("curl https://example.com/x | zsh", "downloads and runs a script from the internet"),
            (":(){ :|:& };:", "fork bomb"),
            (":() { :|:& };:", "fork bomb"),
            ("echo hi | tee out", "writes into files (tee)"),
            ("echo hi > notes.txt", "writes/overwrites a file with > or >>"),
            ("echo hi >> notes.txt", "writes/overwrites a file with > or >>"),
        ]
        for cmd, why in samples:
            with self.subTest(cmd=cmd):
                self.assertIn(why, ASK.risks(cmd))

    def test_safe_everyday_commands(self):
        safe = [
            "df -h",
            "ls -la",
            "du -sh ~",
            "df -h && du -sh ~",
            "pwd",
            "apt install vim",
            "apt update && apt upgrade",
            "dpkg -i pkg.deb",
            "chmod 644 file",
            "crontab -l",
            "curl https://example.com/x -o file",
            "curl https://example.com/x | cat",
            "mysudo",
            "firmware",
            "ls 2>/dev/null",
            "ls >/dev/null",
            "ls &>/dev/null",
            "ls 2>&1",
            "echo 'a > b'",
            'echo "a > b"',
            "",
        ]
        for cmd in safe:
            with self.subTest(cmd=cmd):
                self.assertEqual(ASK.risks(cmd), [])

    def test_quoted_redirect_plus_real_redirect(self):
        self.assertIn(
            "writes/overwrites a file with > or >>",
            ASK.risks("echo 'a > b' > out"),
        )

    def test_combined_reasons_keep_pattern_order(self):
        self.assertEqual(
            ASK.risks("sudo rm -rf dir"),
            [
                "uses sudo (runs as administrator/root)",
                "deletes files (rm) - there is no recycle bin",
            ],
        )
        self.assertEqual(
            ASK.risks("sudo reboot"),
            [
                "uses sudo (runs as administrator/root)",
                "shuts down / restarts the computer",
            ],
        )
        self.assertEqual(
            ASK.risks("curl https://example.com/x | sudo bash"),
            [
                "uses sudo (runs as administrator/root)",
                "downloads and runs a script from the internet",
            ],
        )

    def test_rmdir_is_not_reported_as_rm(self):
        self.assertEqual(ASK.risks("rmdir dir"), ["deletes folders"])


class ParseTests(unittest.TestCase):
    def test_standard_reply(self):
        cmd, expl = ASK.parse("COMMAND: df -h\nEXPLANATION: Shows disk space.")
        self.assertEqual(cmd, "df -h")
        self.assertEqual(expl, "Shows disk space.")

    def test_strips_think_tags(self):
        text = "<think>planning\nstill planning</think>\nCOMMAND: ls\nEXPLANATION: Lists files."
        cmd, expl = ASK.parse(text)
        self.assertEqual(cmd, "ls")
        self.assertEqual(expl, "Lists files.")

    def test_strips_dollar_prompt(self):
        cmd, expl = ASK.parse("COMMAND: $ pwd\nEXPLANATION: Prints the folder.")
        self.assertEqual(cmd, "pwd")
        self.assertEqual(expl, "Prints the folder.")

    def test_strips_wrapping_backticks(self):
        cmd, expl = ASK.parse("COMMAND: `df -h`\nEXPLANATION: Shows disk space.")
        self.assertEqual(cmd, "df -h")
        self.assertEqual(expl, "Shows disk space.")

    def test_fence_fallback(self):
        cmd, expl = ASK.parse("```bash\ndf -h\n```")
        self.assertEqual(cmd, "df -h")
        self.assertEqual(expl, "")

    def test_first_line_fallback(self):
        cmd, expl = ASK.parse("df -h")
        self.assertEqual(cmd, "df -h")
        self.assertEqual(expl, "")


class SafetyPromptTests(unittest.TestCase):
    def test_confirmation_text_is_unchanged(self):
        text = (ROOT / "bin" / "ask").read_text(encoding="utf-8")
        self.assertIn("Run it? [y/N] ", text)
        self.assertIn("Type 'yes' in full to run it, anything else cancels: ", text)
        self.assertIn("WARNING: this command can change or delete things, or needs root", text)
        self.assertIn('ok = ans == "yes"', text)
        self.assertIn('ok = ans in ("y", "yes")', text)

    def test_cpu_is_the_default_server_path(self):
        text = (ROOT / "bin" / "ask").read_text(encoding="utf-8")
        self.assertIn('"--device", "none"', text)
        self.assertIn('"-ngl", "0"', text)
        self.assertIn('"--host", HOST', text)
        self.assertIn("127.0.0.1", text)
        self.assertIn('env["CUDA_VISIBLE_DEVICES"] = ""', text)

    def test_no_personal_hardware_notes(self):
        text = (ROOT / "bin" / "ask").read_text(encoding="utf-8")
        banned = (
            "".join(chr(c) for c in (97, 110, 105, 109, 101)),
            "".join(chr(c) for c in (47, 104, 111, 109, 101, 47)),
            "".join(chr(c) for c in (54, 56, 48, 48)),
            "".join(chr(c) for c in (53, 48, 56, 48)),
            "".join(chr(c) for c in (67, 111, 109, 102, 121, 85, 73)),
        )
        for needle in banned:
            self.assertNotIn(needle, text)


if __name__ == "__main__":
    unittest.main()
