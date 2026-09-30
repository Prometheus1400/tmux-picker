from pathlib import Path
import shlex


class Codex:
    events = {"SessionStart": ("idle", "session started"),
              "UserPromptSubmit": ("working", "prompt submitted"),
              "PreToolUse": ("working", "using tool"),
              "PostToolUse": ("working", "tool finished"),
              "PermissionRequest": ("waiting", "approval requested"),
              "Stop": ("idle", "turn completed"),
              "Interrupt": ("idle", "interrupted"),
              "SessionEnd": ("stopped", "session ended")}

    @staticmethod
    def matches(process):
        if Path(process["command"]).name != "codex":
            return False
        try:
            args = shlex.split(process["args"])[1:]
        except ValueError:
            return False
        return not any(arg in {"app-server", "exec-server", "mcp", "features", "doctor",
                               "completion", "login", "logout", "update", "debug", "plugin"} for arg in args)
