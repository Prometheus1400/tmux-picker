"""Exercise action compatibility, pending feedback, and real fzf repaint timing."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUA = os.environ.get("LUA_BIN", "luajit")

PLUGIN = r'''
return {api_version=1,id="example",setup=function(ctx)
  ctx.register_view({id="example",key="ctrl-g",chord="C-g",label="example",prompt="> ",list=function() end})
  local function record(stage,row,view)
    local f=assert(io.open(os.getenv("ACTION_LOG"),"a"))
    f:write(ctx.json.encode({stage=stage,target=row.target,kind=row.kind,view=view}),"\n");f:close()
  end
  local function run(row,view)
    record("run",row,view)
    return {reload=true,view=view,notice="done (ok)+again"}
  end
  ctx.register_action("example.function",run)
  ctx.register_action("example.table",{run=run})
  for _, name in ipairs({"nil","empty","number","bad","pending"}) do
    ctx.register_action("example."..name,{
      pending=function(row,view)
        record("pending",row,view)
        if name=="bad" then error("pending failed") end
        if name=="empty" then return "" end
        if name=="number" then return 42 end
        if name=="pending" then return "WORKING (archive)+again" end
      end,run=run})
  end
  for _, name in ipairs({"ignore","raw","string","error","slow"}) do
    ctx.register_action("example."..name,{
      pending=function(row,view) record("pending",row,view);return "WORKING (archive)+again" end,
      run=function(row,view)
        record("run",row,view)
        if name=="slow" then ctx.util.run("sleep 2");record("finished",row,view);return {reload=true,view=view,notice="DONE"} end
        if name=="error" then error("run failed") end
        if name=="raw" then return {raw="change-query(raw)"} end
        if name=="string" then return "change-query(string)" end
      end})
  end
end}
'''


class ActionsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="picker-actions-")
        self.home = Path(self.tmp.name)
        config = self.home / "config/tmux-picker"
        plugins = config / "plugins"
        plugins.mkdir(parents=True)
        (plugins / "example.lua").write_text(PLUGIN)
        fake = self.home / "go/bin"
        fake.mkdir(parents=True)
        for name in ("tmux", "fzf"):
            file = fake / name
            file.write_text("#!/bin/sh\nexit 0\n")
            file.chmod(0o755)
        # If a helper accidentally reconciles, this declaration creates managed state.
        (config / "init.lua").write_text('return {bundled_plugins=false,plugins={{repo="/missing",name="unused",enabled=false}}}')
        self.log = self.home / "events"
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / "config"),
                        XDG_DATA_HOME=str(self.home / "data"), XDG_RUNTIME_DIR=str(self.home),
                        TMUX_PICKER_ROOT=str(ROOT), TMUX_PICKER_CMD=str(ROOT / "bin/tmux-picker"),
                        LUA_PATH=str(ROOT / "lua/?.lua") + ";" + str(ROOT / "lua/?/init.lua") + ";;",
                        ACTION_LOG=str(self.log))
        for name in ("TMUX_PICKER_DISABLE_PLUGINS", "TMUX_PICKER_PLUGIN_DIR", "TMUX"):
            self.env.pop(name, None)
        (self.home / "tmux-picker.view").write_text("example\n")

    def tearDown(self):
        self.tmp.cleanup()

    def call(self, command, name, target="target", view=None):
        args = [LUA, str(ROOT / "lua/tmux_picker/main.lua"), command, "example." + name, "example", target]
        if view is not None:
            args.append(view)
        return subprocess.check_output(args, env=self.env, text=True).strip()

    def events(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_function_and_immediate_descriptors(self):
        for name in ("function", "table", "nil", "empty", "number", "bad"):
            with self.subTest(name=name):
                self.log.unlink(missing_ok=True)
                result = self.call("action", name)
                self.assertIn("reload(", result)
                self.assertIn("done (ok)+again", result)
                self.assertNotIn("bg-transform", result)
                self.assertEqual(sum(e["stage"] == "run" for e in self.events()), 1)
        self.assertFalse((self.home / "data").exists())

    def test_pending_defers_work_and_captures_arguments(self):
        target = "project's (archive)+{q} folder"
        result = self.call("action", "pending", target)
        self.assertIn("WORKING (archive)+again", result)
        self.assertIn("+bg-transform:", result)
        self.assertIn("\\{q}", result)
        self.assertEqual([e["stage"] for e in self.events()], ["pending"])
        result = self.call("execute-action", "pending", target, "example")
        self.assertNotIn("WORKING", result)
        self.assertIn("done (ok)+again", result)
        self.assertEqual([e["stage"] for e in self.events()], ["pending", "run"])
        self.assertEqual(self.events()[-1]["target"], target)
        self.assertEqual(self.events()[-1]["view"], "example")
        self.assertFalse((self.home / "data").exists())

    def test_completion_clears_pending_for_all_result_types(self):
        for name, expected in (("ignore", "ignore"), ("raw", "change-query(raw)"),
                               ("string", "change-query(string)"), ("error", "ignore"), ("missing", "ignore")):
            with self.subTest(name=name):
                result = self.call("execute-action", name, view="example")
                self.assertTrue(result.startswith("change-header"))
                self.assertTrue(result.endswith(expected))
                self.assertNotIn("WORKING", result)
        self.assertEqual(self.call("action", "missing"), "ignore")

    def test_invalid_descriptor_rolls_back_plugin(self):
        source = r'''
local registry=require("tmux_picker.registry")
for _, handler in ipairs({{}, {run=true}, {run=function() end,pending="wrong"}}) do
  assert(not pcall(registry.register_action,"invalid",handler))
  assert(not registry.action("invalid"))
end
'''
        subprocess.run([LUA, "-"], env=self.env, input=source, text=True, check=True)
        plugin = self.home / "config/tmux-picker/plugins/example.lua"
        plugin.write_text('return {api_version=1,id="bad",setup=function(ctx) ctx.register_view({id="partial"});ctx.register_action("bad",{}) end}')
        source = 'local r=require("tmux_picker.registry");assert(not r.load_plugin(' + json.dumps(str(plugin)) + '));assert(not r.view("partial"))'
        subprocess.run([LUA, "-"], env=self.env, input=source, text=True, check=True)

    def test_real_fzf_paints_before_work_finishes(self):
        fzf = shutil.which("fzf")
        if not fzf:
            self.skipTest("fzf is unavailable")
        version = subprocess.check_output([fzf, "--version"], text=True).split()[0]
        if tuple(int(x) for x in version.split(".")[:2]) < (0, 71):
            self.skipTest("interactive test requires the documented fzf 0.71+")
        socket = str(self.home / "tmux.sock")
        tmux_bin = shutil.which("tmux")
        def tmux(*args):
            return subprocess.check_output([tmux_bin, "-S", socket, *args], env=self.env, text=True)
        target = "project's (archive)+{q} folder"
        row = "example\t" + target + "\tExample\t\t\n"
        script = self.home / "picker.sh"
        binding = "ctrl-r:transform:" + shlex.quote(str(ROOT / "bin/tmux-picker")) + " action example.slow {1} {2}"
        script.write_text("printf %s " + shlex.quote(row) + " | " + shlex.quote(fzf)
                          + " --reverse --no-clear --ansi --delimiter '\t' --with-nth 3 --header READY --bind " + shlex.quote(binding))
        def wait_for(predicate, timeout=5):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if predicate():
                    return
                time.sleep(0.03)
            self.fail("Timed out waiting for fzf feedback")
        try:
            tmux("-f", "/dev/null", "new-session", "-d", "-s", "test", "-x", "140", "-y", "24", "sh " + shlex.quote(str(script)))
            wait_for(lambda: "READY" in tmux("capture-pane", "-p", "-t", "test"))
            tmux("send-keys", "-t", "test", "C-r")
            wait_for(lambda: "WORKING (archive)+again" in tmux("capture-pane", "-p", "-t", "test"))
            self.assertNotIn("finished", [e["stage"] for e in self.events()])
            wait_for(lambda: "DONE" in tmux("capture-pane", "-p", "-t", "test"))
            capture = tmux("capture-pane", "-p", "-t", "test")
            self.assertNotIn("WORKING", capture)
            self.assertEqual([e["stage"] for e in self.events()], ["pending", "run", "finished"])
            self.assertTrue(all(e["target"] == target and e["view"] == "example" for e in self.events()))
        finally:
            subprocess.run([tmux_bin, "-S", socket, "kill-server"], capture_output=True)


if __name__ == "__main__":
    unittest.main()
