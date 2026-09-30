local M = {}

M.api_version = 1
M.home = os.getenv("HOME") or ""
M.config_home = os.getenv("XDG_CONFIG_HOME") or (M.home .. "/.config")
M.state_home = os.getenv("XDG_STATE_HOME") or (M.home .. "/.local/state")
M.runtime_dir = os.getenv("XDG_RUNTIME_DIR") or os.getenv("TMPDIR") or "/tmp"
M.plugin_dir = os.getenv("TMUX_PICKER_PLUGIN_DIR") or (M.config_home .. "/tmux-picker/plugins")

M.size = "70%,80%"
M.preview_window = "up,55%"
M.hidden_sessions = { scratch = true }
M.tab = "\t"

M.colors = {
	reset = "\27[0m",
	muted = "\27[38;2;108;112;134m",
	green = "\27[38;2;166;227;161m",
	peach = "\27[38;2;250;179;135m",
	blue = "\27[38;2;137;180;250m",
	teal = "\27[38;2;148;226;213m",
	yellow = "\27[38;2;249;226;175m",
	mauve = "\27[38;2;203;166;247m",
}

M.icons = {
	git = "󰘬",
	session = "",
	zoxide = "󰉋",
	window = "",
	pane = "",
}

M.path_prefix = "/opt/homebrew/bin:/usr/local/bin:"
	.. M.home
	.. "/go/bin:"
	.. M.home
	.. "/.nix-profile/bin:"
	.. (os.getenv("PATH") or "/usr/bin")

local runtime_prefix = M.runtime_dir .. "/tmux-picker"
M.prompt_file = runtime_prefix .. ".prompt"
M.tmux_sock_file = runtime_prefix .. ".tmux-sock"
M.view_file = runtime_prefix .. ".view"

return M
