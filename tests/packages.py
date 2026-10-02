"""Declarative plugin reconciliation using real local Git repositories."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("packages", str(ROOT / "bin/tmux-picker-plugins"))
spec = importlib.util.spec_from_loader(loader.name, loader)
packages = importlib.util.module_from_spec(spec)
loader.exec_module(packages)

PLUGIN = '''return {api_version=1, id="demo", setup=function(ctx)
ctx.register_view({id="demo", key="ctrl-k", prompt="demo > ", list=function()
ctx.emit({kind="demo", target="demo", name="MESSAGE"}) end})
ctx.register_kind("demo", {}) end}'''


class PackagesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="picker packages' ")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.repo = self.home / "origin"
        self.repo.mkdir()
        packages.git(self.repo, "init", "-b", "main")
        packages.git(self.repo, "config", "user.name", "Test")
        packages.git(self.repo, "config", "user.email", "test@example.com")
        self.commit("first")
        packages.git(self.repo, "tag", "v1")
        self.directory = self.home / "data/plugins"
        self.declaration = {"name": "demo", "repo": str(self.repo), "entry": "plugin.lua", "enabled": True}

    def commit(self, text):
        (self.repo / "plugin.lua").write_text(PLUGIN.replace("MESSAGE", text))
        packages.git(self.repo, "add", "plugin.lua")
        packages.git(self.repo, "commit", "-m", text)
        return packages.git(self.repo, "rev-parse", "HEAD")

    def sync(self, specs=None, interval=86400):
        return packages.reconcile({"specs": [self.declaration] if specs is None else specs,
                                   "directory": str(self.directory), "update_interval": interval})

    def index(self):
        return json.loads((self.directory / "index.json").read_text())

    def test_install_cached_update_pins_disable_and_remove(self):
        self.assertEqual(self.sync()["errors"], [])
        path = self.directory / "demo"
        first = packages.git(path, "rev-parse", "HEAD")
        second = self.commit("second")
        self.sync()
        self.assertEqual(packages.git(path, "rev-parse", "HEAD"), first)
        self.sync(interval=0)
        self.assertEqual(packages.git(path, "rev-parse", "HEAD"), second)
        self.declaration["version"] = "v1"
        self.sync()
        self.assertEqual(packages.git(path, "rev-parse", "HEAD"), first)
        self.commit("third")
        self.sync(interval=0)
        self.assertEqual(packages.git(path, "rev-parse", "HEAD"), first)
        self.declaration["enabled"] = False
        self.sync(interval=0)
        self.assertTrue(path.exists())
        self.sync([])
        self.assertFalse(path.exists())
        self.assertEqual(self.index()["packages"], [])

    def test_local_changes_and_offline_failure_preserve_checkout(self):
        self.sync()
        path = self.directory / "demo"
        (path / "plugin.lua").write_text("user modification")
        self.assertIn("local changes preserved", self.sync([], 0)["errors"][0])
        self.assertTrue(path.exists())
        self.assertIn("local changes preserved", self.sync(interval=0)["errors"][0])
        packages.git(path, "restore", "plugin.lua")
        (path / ".git/info/exclude").write_text(".local-settings\n")
        (path / ".local-settings").write_text("user settings")
        self.assertIn("local changes preserved", self.sync([])["errors"][0])
        (path / ".local-settings").unlink()
        moved = self.home / "offline"
        self.repo.rename(moved)
        self.assertTrue(self.sync(interval=0)["errors"])
        self.assertIn("first", (path / "plugin.lua").read_text())

    def test_disabled_not_installed_and_bad_entry_rolls_back(self):
        self.declaration["enabled"] = False
        self.sync()
        self.assertFalse((self.directory / "demo").exists())
        self.declaration["enabled"] = True
        self.sync()
        before = packages.git(self.directory / "demo", "rev-parse", "HEAD")
        self.commit("second")
        self.declaration["entry"] = "missing.lua"
        self.assertTrue(self.sync(interval=0)["errors"])
        self.assertEqual(packages.git(self.directory / "demo", "rev-parse", "HEAD"), before)

    def test_validation_and_unmanaged_directory(self):
        with self.assertRaises(ValueError):
            self.sync([{**self.declaration, "name": "../escape"}])
        self.assertFalse(self.directory.exists())
        (self.directory / "demo").mkdir(parents=True)
        (self.directory / "demo/user.txt").write_text("preserve")
        self.assertIn("unmanaged path", self.sync()["errors"][0])
        self.assertEqual((self.directory / "demo/user.txt").read_text(), "preserve")

    def test_commit_pin_and_transactional_repository_change(self):
        first = packages.git(self.repo, "rev-parse", "HEAD")
        self.declaration["version"] = first
        self.sync()
        self.commit("second")
        self.sync(interval=0)
        self.assertEqual(packages.git(self.directory / "demo", "rev-parse", "HEAD"), first)
        broken = self.home / "broken"
        broken.mkdir()
        packages.git(broken, "init", "-b", "main")
        self.declaration["repo"] = str(broken)
        self.assertTrue(self.sync()["errors"])
        self.assertEqual(packages.git(self.directory / "demo", "rev-parse", "HEAD"), first)

    def test_picker_reconciles_config_without_cli_commands(self):
        home = self.home
        config = home / "config/tmux-picker/init.lua"
        config.parent.mkdir(parents=True)
        fake = home / "go/bin/fzf"
        fake.parent.mkdir(parents=True)
        fake.write_text('#!/bin/sh\ncat > "$HOME/rows"\n')
        fake.chmod(0o755)
        fake_tmux = home / "go/bin/tmux"
        fake_tmux.write_text("#!/bin/sh\nexit 0\n")
        fake_tmux.chmod(0o755)
        env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / "config"),
                   XDG_DATA_HOME=str(home / "data"), XDG_RUNTIME_DIR=str(home), TMPDIR=str(home),
                   TMUX_PICKER_ROOT=str(ROOT), LUA_BIN=os.environ.get("LUA_BIN", "luajit"))
        for key in ("TMUX", "TMUX_PANE", "TMUX_PICKER_DISABLE_PLUGINS", "TMUX_PICKER_PLUGIN_DIR", "FZF_DEFAULT_OPTS_FILE"):
            env.pop(key, None)
        def configure(enabled=True, declared=True):
            spec = 'repo=' + json.dumps(str(self.repo)) + ',name="demo",enabled=' + str(enabled).lower()
            config.write_text('return {bundled_plugins={windows=false,panes=false,zoxide=false,agents=false},plugins={' + ('{' + spec + '}' if declared else '') + '}}')
        def run(*args):
            return subprocess.check_output([str(ROOT / "bin/tmux-picker"), *args], env=env, text=True)
        configure()
        run("demo")
        self.assertIn("first", (home / "rows").read_text())
        self.commit("second")
        run("demo")
        self.assertIn("first", (home / "rows").read_text())
        configure(enabled=False)
        self.assertEqual(run("list", "demo"), "")
        configure(declared=False)
        # Opening performs reconciliation; helper subprocesses never mutate repos.
        run("list", "demo")
        self.assertTrue((home / "data/tmux-picker/plugins/demo").exists())
        run("demo")
        self.assertFalse((home / "data/tmux-picker/plugins/demo").exists())


if __name__ == "__main__":
    unittest.main()
