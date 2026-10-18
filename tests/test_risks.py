#!/usr/bin/env python3
"""Unit tests for the dangerous-command detector and the CPU-only server setup."""
import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOADER = importlib.machinery.SourceFileLoader("ask", str(ROOT / "bin" / "ask"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
ask = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(ask)


class RisksTest(unittest.TestCase):
    def assertSafe(self, cmd):
        self.assertEqual(ask.risks(cmd), [], cmd)

    def assertDanger(self, cmd, fragment):
        found = ask.risks(cmd)
        self.assertTrue(found, cmd)
        self.assertTrue(
            any(fragment in why for why in found),
            f"{cmd!r} -> {found!r} missing {fragment!r}",
        )

    def test_everyday_commands_are_safe(self):
        for cmd in (
            "df -h",
            "ls -la",
            "pwd",
            "date",
            "cat notes.txt",
            "echo hello",
            "echo hello 2>/dev/null",
            "echo hello 2>&1",
            "echo hello >/dev/null",
            "echo '>'",
            'echo "a > b"',
            "apt-get install vim",
            "dnf install vim",
            "pacman -Syu",
            "chmod 644 notes.txt",
        ):
            self.assertSafe(cmd)

    def test_sudo_and_user_switch(self):
        self.assertDanger("sudo ls", "sudo")
        self.assertDanger("sudo apt update", "sudo")
        self.assertDanger("su -", "another user")
        self.assertDanger("doas ls", "another user")
        self.assertDanger("pkexec ls", "another user")

    def test_delete_and_disk_tools(self):
        self.assertDanger("rm notes.txt", "rm")
        self.assertDanger("rm -rf /tmp/scratch", "rm")
        self.assertDanger("rmdir empty", "folders")
        self.assertDanger("dd if=/dev/zero of=/dev/sda", "dd")
        self.assertDanger("mkfs.ext4 /dev/sdb1", "formats")
        self.assertDanger("fdisk /dev/sda", "partition")
        self.assertDanger("shred secret.txt", "destroys")
        self.assertDanger("truncate -s 0 notes.txt", "empty files")

    def test_permissions_services_and_packages(self):
        self.assertDanger("chmod -R 777 /tmp/project", "chmod -R")
        self.assertDanger("chown user notes.txt", "chown")
        self.assertDanger("systemctl restart ssh", "systemctl")
        self.assertDanger("apt-get remove vim", "removes software")
        self.assertDanger("apt purge vim", "removes software")
        self.assertDanger("dnf remove vim", "removes software")
        self.assertDanger("yum erase vim", "removes software")
        self.assertDanger("zypper remove vim", "removes software")
        self.assertDanger("pacman -Rns vim", "pacman")
        self.assertDanger("snap remove firefox", "removes software")

    def test_process_power_and_move(self):
        self.assertDanger("shutdown now", "shuts down")
        self.assertDanger("reboot", "shuts down")
        self.assertDanger("kill 123", "stops running")
        self.assertDanger("pkill firefox", "stops running")
        self.assertDanger("mv a b", "moves")
        self.assertDanger("crontab -r", "scheduled")

    def test_download_and_run_and_fork_bomb(self):
        self.assertDanger("curl https://example.com/x.sh | bash", "internet")
        self.assertDanger("wget -O - https://example.com/x.sh | sh", "internet")
        self.assertDanger(":(){ :|:& };:", "fork bomb")

    def test_writes(self):
        self.assertDanger("echo hello > notes.txt", ">")
        self.assertDanger("echo hello >> notes.txt", ">")
        self.assertDanger("echo hello | tee notes.txt", "tee")

    def test_several_reasons_keep_list_order(self):
        found = ask.risks("sudo rm notes.txt")
        self.assertGreaterEqual(len(found), 2)
        self.assertIn("sudo", found[0])
        self.assertIn("rm", found[1])

    def test_safety_prompts_stay_in_the_program(self):
        text = (ROOT / "bin" / "ask").read_text(encoding="utf-8")
        self.assertIn("Run it? [y/N]", text)
        self.assertIn("Type 'yes' in full to run it, anything else cancels:", text)
        self.assertIn("WARNING: this command can change or delete things, or needs root", text)
        self.assertIn("Read it carefully. If you are not sure, do NOT run it.", text)
        self.assertIn('ok = ans == "yes"', text)
        self.assertIn('ok = ans in ("y", "yes")', text)


class ParseTest(unittest.TestCase):
    def test_command_and_explanation(self):
        cmd, expl = ask.parse("COMMAND: df -h\nEXPLANATION: Shows disk space.")
        self.assertEqual(cmd, "df -h")
        self.assertEqual(expl, "Shows disk space.")

    def test_think_tags_are_ignored(self):
        cmd, expl = ask.parse("<think>secret</think>\nCOMMAND: ls\nEXPLANATION: Lists files.")
        self.assertEqual(cmd, "ls")
        self.assertEqual(expl, "Lists files.")

    def test_fenced_command_strips_prompt(self):
        cmd, _expl = ask.parse("```bash\n$ pwd\n```")
        self.assertEqual(cmd, "pwd")


class ServerSetupTest(unittest.TestCase):
    def test_defaults_to_cpu_on_localhost(self):
        self.assertEqual(ask.HOST, "127.0.0.1")
        self.assertEqual(ask.PORT, 8742)
        argv = ask.server_argv("/opt/llama-server", False)
        self.assertEqual(argv[argv.index("--host") + 1], "127.0.0.1")
        self.assertEqual(argv[argv.index("--port") + 1], "8742")
        self.assertEqual(argv[argv.index("--device") + 1], "none")
        self.assertEqual(argv[argv.index("-ngl") + 1], "0")
        self.assertIn("--no-webui", argv)
        self.assertIn("--reasoning", argv)
        self.assertEqual(argv[argv.index("--reasoning") + 1], "off")

    def test_cuda_opt_in_drops_the_cpu_lock(self):
        argv = ask.server_argv("/opt/llama-server", True)
        self.assertNotIn("--device", argv)
        self.assertEqual(argv[argv.index("-ngl") + 1], "99")
        self.assertEqual(argv[argv.index("--host") + 1], "127.0.0.1")

    def test_cpu_env_hides_gpus(self):
        env = ask.server_env({"PATH": "/usr/bin", "CUDA_VISIBLE_DEVICES": "0"}, False)
        self.assertEqual(env["CUDA_VISIBLE_DEVICES"], "")
        self.assertEqual(env["HIP_VISIBLE_DEVICES"], "-1")
        self.assertEqual(env["ROCR_VISIBLE_DEVICES"], "-1")
        self.assertTrue(env["LD_LIBRARY_PATH"].startswith(ask.LLAMA_DIR + ":"))

    def test_cuda_env_keeps_cuda_visible(self):
        env = ask.server_env({"CUDA_VISIBLE_DEVICES": "0"}, True)
        self.assertEqual(env["CUDA_VISIBLE_DEVICES"], "0")
        self.assertEqual(env["HIP_VISIBLE_DEVICES"], "-1")

    def test_backend_file_and_env(self):
        old = os.environ.pop("COMMAND_HELPER_BACKEND", None)
        old_home = ask.HOME
        home = tempfile.mkdtemp()
        ask.HOME = home
        try:
            self.assertFalse(ask.wants_cuda())
            os.makedirs(os.path.join(home, ".config", "command-helper"))
            backend = os.path.join(home, ".config", "command-helper", "backend")
            with open(backend, "w", encoding="utf-8") as handle:
                handle.write("cuda\n")
            self.assertTrue(ask.wants_cuda())
            os.environ["COMMAND_HELPER_BACKEND"] = "cpu"
            self.assertFalse(ask.wants_cuda())
            os.environ["COMMAND_HELPER_BACKEND"] = "cuda"
            self.assertTrue(ask.wants_cuda())
        finally:
            ask.HOME = old_home
            if old is None:
                os.environ.pop("COMMAND_HELPER_BACKEND", None)
            else:
                os.environ["COMMAND_HELPER_BACKEND"] = old


if __name__ == "__main__":
    unittest.main()
