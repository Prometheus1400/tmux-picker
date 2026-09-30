from pathlib import Path
import shlex
import json


def recent_messages(path, limit=8, max_bytes=262144):
    """Read a bounded transcript tail; tool calls and reasoning stay out."""
    with open(path, "rb") as stream:
        stream.seek(0, 2)
        start = max(0, stream.tell() - max_bytes)
        stream.seek(start)
        if start:
            stream.readline()  # Ignore a possibly partial first JSON record.
        lines = stream.read(max_bytes).decode("utf-8", errors="replace").splitlines()
    messages = []
    legacy = []
    for line in lines:
        try:
            entry = json.loads(line)
            payload = entry.get("payload", {})
            if entry.get("type") == "response_item" and payload.get("type") == "message":
                role = payload.get("role")
                if role not in {"user", "assistant"} or payload.get("channel") == "analysis":
                    continue
                text = "\n".join(part.get("text", "") for part in payload.get("content", [])
                                 if part.get("type") in {"input_text", "output_text", "text"})
                if role == "user" and text.lstrip().startswith(("<environment_context>", "# AGENTS.md instructions", "<user_instructions>")):
                    continue
                destination = messages
            elif entry.get("type") == "event_msg" and payload.get("type") in {"user_message", "agent_message"}:
                role = "user" if payload["type"] == "user_message" else "assistant"
                text = payload.get("message", "")
                destination = legacy
            else:
                continue
            if not isinstance(text, str) or not text.strip():
                continue
            text = text.strip()
            if len(text) > 1600:
                text = text[:1600] + "\n… (message shortened)"
            destination.append({"role": role, "text": text})
        except (ValueError, AttributeError, TypeError):
            continue
    # Old versions use event messages; never mix both encodings and duplicate turns.
    return (messages or legacy)[-limit:]


class Codex:
    @staticmethod
    def conversation(record):
        path = record.get("transcript_path")
        if not path:
            return {"messages": [], "notice": "No conversation linked yet. Review /hooks in Codex, then refresh after the next turn."}
        try:
            messages = recent_messages(path)
        except (OSError, ValueError):
            return {"messages": [], "notice": "The linked Codex transcript is unavailable."}
        return {"messages": messages, "notice": "" if messages else "No recent conversation messages in this transcript format."}

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
