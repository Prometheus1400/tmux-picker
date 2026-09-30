"""Exercise real TPM installation in an isolated tmux server."""
import os
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TPM = Path(os.environ.get("TPM_SOURCE", Path.home() / ".tmux/plugins/tpm")).resolve()
if not (TPM / "tpm").is_file():
    raise SystemExit("Set TPM_SOURCE to a checkout of tmux-plugins/tpm")

with tempfile.TemporaryDirectory(prefix="tmux-picker-tpm-") as temporary:
    home = Path(temporary)
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / "config"),
               XDG_RUNTIME_DIR=str(home), TMPDIR=str(home), TMUX_PANE="")
    env.pop("TMUX", None)
    env.pop("TMUX_PICKER_ROOT", None)
    env.pop("TMUX_PICKER_PLUGIN_DIR", None)
    env.pop("TMUX_PICKER_DISABLE_PLUGINS", None)
    socket = "picker-test-" + str(os.getpid())

    def run(*args, **kwargs):
        try:
            return subprocess.check_output(args, env=env, text=True, stderr=subprocess.STDOUT, **kwargs).strip()
        except subprocess.CalledProcessError as error:
            print(error.output)
            raise

    def tmux(*args):
        return run("tmux", "-L", socket, *args)

    def option(name):
        return tmux("show-option", "-gqv", name)

    def binding(key):
        result = subprocess.run(["tmux", "-L", socket, "list-keys", "-T", "prefix", key],
                                env=env, text=True, capture_output=True)
        return result.stdout.strip() if result.returncode == 0 else ""

    # Publish the current working tree to a temporary Git remote for TPM to clone.
    origin = home / "origin/tmux-picker"
    origin.mkdir(parents=True)
    for name in ("bin", "lua", "plugins", "tests", "tmux-picker.tmux", "README.md", "LICENSE"):
        source = ROOT / name
        if source.is_dir():
            shutil.copytree(source, origin / name)
        else:
            shutil.copy2(source, origin / name)
    run("git", "init", "-q", "-b", "main", str(origin))
    run("git", "-C", str(origin), "add", ".")
    run("git", "-C", str(origin), "-c", "user.name=TPM Test", "-c", "user.email=test@example.com",
        "commit", "-qm", "Integration fixture")
    installed = home / ".tmux/plugins/tmux-picker"
    installed.parent.mkdir(parents=True)
    config = home / ".tmux.conf"
    config.write_text("set -g @plugin " + shlex.quote(str(origin)) + "\n")
    try:
        tmux("-f", "/dev/null", "new-session", "-d", "-s", "test")
        env["TMUX"] = tmux("display-message", "-p", "#{socket_path}") + ",0,0"
        tmux("set-environment", "-g", "TMUX_PLUGIN_MANAGER_PATH", str(installed.parent) + "/")
        tmux("source-file", str(config))
        output = run("bash", str(TPM / "bin/install_plugins"))
        assert (installed / "tmux-picker.tmux").is_file(), output
        run("bash", str(TPM / "tpm"))
        assert "run-shell" in binding("o"), "TPM did not install Prefix-o"
        # The generated command uses single quotes even for paths without spaces.
        assert option("@tmux-picker-command") == "'" + str(installed / "bin/tmux-picker") + "'"
        first_binding = binding("o")
        run("bash", str(TPM / "tpm"))
        assert binding("o") == first_binding, "Initialization is not idempotent"

        tmux("set-option", "-g", "@tmux-picker-key", "s")
        run("bash", str(installed / "tmux-picker.tmux"))
        assert not binding("o") and "run-shell" in binding("s")
        tmux("set-option", "-g", "@tmux-picker-key", "")
        run("bash", str(installed / "tmux-picker.tmux"))
        assert not binding("s"), "Explicitly empty key installed a binding"
        tmux("set-option", "-gu", "@tmux-picker-key")
        run("bash", str(installed / "tmux-picker.tmux"))
        assert binding("o")

        # Relocation and shell quoting must work outside the default plugin path.
        relocated = home / "relocated picker's checkout"
        shutil.copytree(installed, relocated)
        run("bash", str(relocated / "tmux-picker.tmux"))
        command = option("@tmux-picker-command")
        assert shlex.split(command) == [str(relocated / "bin/tmux-picker")]
        assert "ok      tmux" in run("sh", "-c", command + " doctor")
        assert "session\t" in run("sh", "-c", command + " list sessions")

        # The new bundled view survives TPM installation and relocated paths.
        assert "agents > " in run("sh", "-c", command + " switch-view agents")
        assert (relocated / "bin/agent_providers/codex.py").is_file()
        run("python3", str(relocated / "bin/tmux-picker-agents"), "install-codex-hooks")
        hooks = json.loads((home / ".codex/hooks.json").read_text())
        assert shlex.split(hooks["hooks"]["Stop"][0]["hooks"][0]["command"]) == [
            str(relocated / "bin/tmux-picker-agents"), "hook", "codex"]
        run("python3", str(relocated / "bin/tmux-picker-agents"), "uninstall-codex-hooks")

        # Preview real nested splits and preserve the layout while zoomed.
        original_pane = tmux("display-message", "-p", "-t", "test", "#{pane_id}")
        window_id = tmux("display-message", "-p", "-t", "test", "#{window_id}")
        right_pane = tmux("split-window", "-h", "-t", original_pane, "-P", "-F", "#{pane_id}", "sleep 60")
        tmux("split-window", "-v", "-t", right_pane, "sleep 60")
        preview_command = "FZF_PREVIEW_COLUMNS=60 FZF_PREVIEW_LINES=16 " + command + " preview window " + window_id
        preview = run("sh", "-c", preview_command)
        assert "┬" in preview and "├" in preview, "Nested split layout missing from preview"
        assert "sleep" in preview, "Pane process names missing from preview"
        tmux("resize-pane", "-Z", "-t", original_pane)
        preview = run("sh", "-c", preview_command)
        assert "(zoomed)" in preview and "┬" in preview and "├" in preview
        tmux("resize-pane", "-Z", "-t", original_pane)

        # Exercise the documented user configuration through the real launcher.
        config_dir = home / "config/tmux-picker"
        user_plugins = config_dir / "plugins"
        user_plugins.mkdir(parents=True)
        shutil.copy2(ROOT / "tests/fixtures/example.lua", user_plugins / "example.lua")
        zoxide = home / "go/bin/zoxide"
        zoxide.parent.mkdir(parents=True)
        zoxide.write_text('#!/bin/sh\nprintf "/tmp\\n"\n')
        zoxide.chmod(0o755)
        user_config = config_dir / "init.lua"
        user_config.write_text("return { bundled_plugins = { zoxide = false } }\n")
        assert run("sh", "-c", command + " switch-view zoxide") == "ignore"
        assert "reload(" in run("sh", "-c", command + " switch-view example")
        user_config.write_text("return { bundled_plugins = { zoxide = true } }\n")
        assert "reload(" in run("sh", "-c", command + " switch-view zoxide")
        user_config.write_text("return { bundled_plugins = false }\n")
        assert run("sh", "-c", command + " switch-view zoxide") == "ignore"
        assert "reload(" in run("sh", "-c", command + " switch-view example")
        env["TMUX_PICKER_DISABLE_PLUGINS"] = "1"
        assert run("sh", "-c", command + " switch-view example") == "ignore"
        assert "reload(" in run("sh", "-c", command + " switch-view windows")
        env.pop("TMUX_PICKER_DISABLE_PLUGINS")

        # Capture the actual fzf environment and arguments from a picker launch.
        fake_fzf = home / "go/bin/fzf"
        fake_fzf.write_text(
            '#!/bin/sh\n'
            'printf "%s\\n" "$FZF_DEFAULT_OPTS" > "$XDG_RUNTIME_DIR/fzf-options"\n'
            'printf "%s\\n" "$@" > "$XDG_RUNTIME_DIR/fzf-arguments"\n'
            'cat >/dev/null\n'
        )
        fake_fzf.chmod(0o755)
        test_path = str(fake_fzf.parent) + ":" + env["PATH"]
        base_config = "return { bundled_plugins = false, path_prefix = " + json.dumps(test_path)
        user_config.write_text(base_config + " }\n")
        env.pop("FZF_DEFAULT_OPTS", None)
        env.pop("FZF_DEFAULT_OPTS_FILE", None)
        run("sh", "-c", command)
        assert (home / "fzf-options").read_text().rstrip("\n") == "--color=16 "
        assert "--color" not in (home / "fzf-arguments").read_text().splitlines()
        theme = "--color=border:#ebbcba,preview-border:#31748f"
        env["FZF_DEFAULT_OPTS"] = theme
        run("sh", "-c", command)
        assert (home / "fzf-options").read_text().rstrip("\n") == "--color=16 " + theme
        options_file = home / "theme-options"
        options_file.write_text("--color=light\n")
        env["FZF_DEFAULT_OPTS_FILE"] = str(options_file)
        run("sh", "-c", command)
        assert (home / "fzf-options").read_text().strip() == theme
        user_config.write_text(base_config + ', fzf_colors = "border:#c4a7e7" }\n')
        run("sh", "-c", command)
        arguments = (home / "fzf-arguments").read_text().splitlines()
        assert arguments[arguments.index("--color") + 1] == "border:#c4a7e7"

        custom = "printf custom-launcher"
        tmux("set-option", "-g", "@tmux-picker-command", custom)
        run("bash", str(installed / "tmux-picker.tmux"))
        assert option("@tmux-picker-command") == custom
        assert "custom-launcher" in binding("o")

        # Changing our key must leave a user-replaced binding untouched.
        tmux("bind-key", "o", "display-message", "user binding")
        tmux("set-option", "-g", "@tmux-picker-key", "")
        run("bash", str(installed / "tmux-picker.tmux"))
        assert "user binding" in binding("o")
        print("TPM integration tests passed: install, bindings, reload, relocation, overrides, plugin selection, layouts, colors")
    finally:
        subprocess.run(["tmux", "-L", socket, "kill-server"], env=env, capture_output=True)
