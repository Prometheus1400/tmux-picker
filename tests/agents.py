"""Agent discovery, status ownership, and non-destructive hook configuration."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin/tmux-picker-agents"
loader = importlib.machinery.SourceFileLoader("agents", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
agents = importlib.util.module_from_spec(spec)
loader.exec_module(agents)


class AgentsTests(unittest.TestCase):
    def test_tree_and_detection(self):
        table = {1: {"parent": 0}, 2: {"parent": 1}, 3: {"parent": 2}, 4: {"parent": 4}}
        self.assertTrue(agents.owns(table, 1, 3))
        self.assertFalse(agents.owns(table, 1, 4))
        self.assertTrue(agents.codex({"command": "/opt/bin/codex", "args": "codex resume abc"}))
        self.assertFalse(agents.codex({"command": "codex", "args": "codex app-server"}))
        self.assertFalse(agents.codex({"command": "sh", "args": "sh -c codex"}))

    def test_hook_and_daemon_ownership(self):
        table = {20: {"pid": 20, "parent": 10, "command": "codex", "args": "codex"},
                 30: {"pid": 30, "parent": 20, "command": "sh", "args": "sh"}}
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, XDG_STATE_HOME=directory, TMUX="socket,0,0", TMUX_PANE="%99"), \
                patch.object(agents, "processes", return_value=table), patch.object(agents.os, "getppid", return_value=30), \
                patch.object(agents, "panes", return_value=[{"pane": "%2", "root": 10}]), \
                patch.object(agents, "identity", return_value="start"):
            agents.record_hook({"session_id": "../../session", "hook_event_name": "PermissionRequest", "cwd": "/repo"})
            record = agents.read_records()[0]
            self.assertEqual((record["pane"], record["pid"], record["status"]), ("%2", 20, "waiting"))
            table[20]["args"] = "codex app-server"
            agents.record_hook({"session_id": "../../session", "hook_event_name": "Stop"})
            record = agents.read_records()[0]
            self.assertEqual(record["pane"], "")
            self.assertIsNone(record["pid"])

    def test_install_uninstall_preserves_user_hooks(self):
        with tempfile.TemporaryDirectory(prefix="agent's config ") as directory, patch.dict(os.environ, CODEX_HOME=directory):
            path = Path(directory) / "hooks.json"
            original = {"description": "user config", "hooks": {"Stop": [{"matcher": "custom", "hooks": [{"type": "command", "command": "user-command"}]}]}}
            path.write_text(json.dumps(original))
            agents.configure_hooks()
            first = path.read_text()
            agents.configure_hooks()
            self.assertEqual(path.read_text(), first)
            self.assertEqual(json.loads(path.with_name("hooks.json.tmux-picker-backup").read_text()), original)
            agents.configure_hooks(remove=True)
            self.assertEqual(json.loads(path.read_text()), original)

    def test_shared_daemon_directory_matching_is_explicit_and_unambiguous(self):
        table = {10: {"pid": 10, "parent": 1, "command": "sh", "args": "sh"},
                 20: {"pid": 20, "parent": 10, "command": "codex", "args": "codex"},
                 30: {"pid": 30, "parent": 1, "command": "codex", "args": "codex app-server"}}
        pane = {"pane": "%2", "root": 10, "cwd": "/repo"}
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, XDG_STATE_HOME=directory, TMUX="socket,0,0", TMUX_PANE="%99"), \
                patch.object(agents, "processes", return_value=table), patch.object(agents.os, "getppid", return_value=30), \
                patch.object(agents, "panes", return_value=[pane]), patch.object(agents, "identity", return_value="start"):
            payload = {"session_id": "session", "hook_event_name": "UserPromptSubmit", "cwd": "/repo"}
            agents.record_hook(payload)
            record = agents.read_records()[0]
            self.assertEqual(record["pane"], "%2")
            self.assertEqual(record["association"], "unique directory (inferred)")
            table[21] = {"pid": 21, "parent": 10, "command": "codex", "args": "codex"}
            agents.record_hook(payload)
            self.assertEqual(agents.read_records()[0]["pane"], "")
            exact = {**record, "association": "process ancestry"}
            key = agents.hashlib.sha256(b"codex:session").hexdigest() + ".json"
            agents.atomic_json(agents.state_dir() / key, exact)
            agents.record_hook(payload)
            self.assertEqual(agents.read_records()[0]["pane"], "%2")
            self.assertEqual(agents.read_records()[0]["association"], "process ancestry")

    def test_lua_view_navigation_and_configuration(self):
        lua = shutil.which(os.environ.get("LUA_BIN", "luajit")) or shutil.which("lua")
        env = dict(os.environ, TMUX_PICKER_ROOT=str(ROOT), LUA_PATH=str(ROOT / "lua/?.lua") + ";;")
        script = '''
local config = require("tmux_picker.config")
local util = require("tmux_picker.util")
local tmux = require("tmux_picker.tmux")
local registry = require("tmux_picker.registry")
local alive = true
util.run = function(command)
  if command:find("command -v", 1, true) then return "/usr/bin/python3" end
  if not alive then return "[]" end
  return '[{"id":"identity","pane":"%2","pid":42,"provider":"codex","status":"working","reason":"tool activity","cwd":"/repo","location":"test:0.1","association":"process ancestry","session_id":"session","updated_at":0}]'
end
tmux.run = function() return "socket" end
local switched
tmux.switch_pane = function(pane) switched = pane end
local notice
util.notify = function(message) notice = message end
local emitted = {}
util.emit = function(row) emitted[#emitted + 1] = row end
assert(registry.load_plugin(config.root .. "/plugins/agents.lua"))
local view = assert(registry.view("agents"))
assert(view.key == "ctrl-g")
view.list()
assert(#emitted == 1 and emitted[1].target == "identity")
local kind = assert(registry.kind("agent"))
kind.accept({target="identity"})
assert(switched == "%2")
switched = nil
alive = false
kind.accept({target="identity"})
assert(switched == nil and notice:find("no longer running"))
alive = true
kind.kill({target="identity"})
assert(notice:find("cannot be killed"))
config.agents.providers.codex = false
emitted = {}
view.list()
assert(#emitted == 0)
assert(registry.action("agents.refresh")({}, "agents").reload)
'''
        subprocess.run([lua, "-"], input=script, text=True, env=env, check=True)

    def test_real_panes_and_stale_status(self):
        with tempfile.TemporaryDirectory(prefix="picker-agents-") as directory:
            home = Path(directory)
            socket = str(home / "tmux.sock")
            binary = home / "codex"
            shutil.copy2(shutil.which("sleep"), binary)
            def tmux(*args):
                return agents.tmux(socket, *args).strip()
            with patch.dict(os.environ, XDG_STATE_HOME=str(home / "state")):
                try:
                    tmux("-f", "/dev/null", "new-session", "-d", "-s", "agents", "-c", directory, str(binary) + " 60")
                    tmux("split-window", "-h", "-t", "agents", "-c", directory, str(binary) + " 60")
                    deadline = time.monotonic() + 5
                    rows = agents.discover(socket)
                    while len(rows) != 2 and time.monotonic() < deadline:
                        time.sleep(0.05)
                        rows = agents.discover(socket)
                    self.assertEqual(len(rows), 2)
                    self.assertEqual({r["status"] for r in rows}, {"unknown"})
                    record = {"version": 1, "provider": "codex", "session_id": "one", "socket": socket,
                              "pane": rows[0]["pane"], "pid": rows[0]["pid"], "process_start": agents.identity(rows[0]["pid"]),
                              "status": "waiting", "reason": "approval requested", "updated_at": 1}
                    agents.atomic_json(agents.state_dir() / "test.json", record)
                    rows = agents.discover(socket)
                    self.assertEqual([r["status"] for r in rows], ["waiting", "unknown"])
                    record["process_start"] = "different process"
                    agents.atomic_json(agents.state_dir() / "test.json", record)
                    self.assertEqual({r["status"] for r in agents.discover(socket)}, {"unknown"})
                    tmux("kill-pane", "-t", rows[0]["pane"])
                    self.assertEqual(len(agents.discover(socket)), 1)
                finally:
                    subprocess.run(["tmux", "-S", socket, "kill-server"], capture_output=True)


if __name__ == "__main__":
    unittest.main()
