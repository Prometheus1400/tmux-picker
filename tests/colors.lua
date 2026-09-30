local config = require("tmux_picker.config")
local loader = require("tmux_picker.loader")
local picker = require("tmux_picker.picker")
local registry = require("tmux_picker.registry")
local tmux = require("tmux_picker.tmux")
local util = require("tmux_picker.util")
local views = require("tmux_picker.views")

-- Defaults must reference the terminal palette rather than fixed RGB values.
for name, color in pairs(config.colors) do
	local code = tonumber(color:match("^\27%[(%d+)m$"))
	assert(code and (code == 0 or code >= 30 and code <= 37 or code >= 90 and code <= 97), name .. " is not a palette color")
end

registry.reset()
views.register()
local original_popen, original_write_file, original_socket = io.popen, util.write_file, tmux.save_socket
local command
io.popen = function(value)
	command = value
	return {
		read = function() return "" end,
		close = function() return true end,
	}
end
util.write_file = function() return true end
tmux.save_socket = function() end
picker.open("sessions", "/tmp/picker's executable")
local user_options = os.getenv("FZF_DEFAULT_OPTS") or ""
local opts_file = os.getenv("FZF_DEFAULT_OPTS_FILE")
local expected_options = opts_file and opts_file ~= "" and user_options or "--color=16 " .. user_options
assert(command:find("FZF_DEFAULT_OPTS=" .. util.shell_quote(expected_options), 1, true), "fzf defaults were not preserved")
assert(not command:find("--color '", 1, true), "picker overrides the global fzf theme by default")
assert(not command:find("#89b4fa", 1, true), "fixed Catppuccin border color remains")

-- Load a partial override through the configuration loader; preserve other colors.
local temporary = os.tmpname()
local handle = assert(io.open(temporary, "w"))
handle:write('return { colors = { blue = "\\27[38;2;156;207;216m" }, fzf_colors = "border:#ebbcba" }\n')
handle:close()
local original_exists, original_dofile = util.file_exists, dofile
local green = config.colors.green
util.file_exists = function() return true end
dofile = function() return original_dofile(temporary) end
loader.configure()
util.file_exists, dofile = original_exists, original_dofile
os.remove(temporary)
assert(config.colors.blue == "\27[38;2;156;207;216m", "configured RGB label override missing")
assert(config.colors.green == green, "partial override removed other default colors")
assert(picker.legend("sessions"):find(config.colors.blue, 1, true), "configured label color not rendered")
picker.open("sessions", "/tmp/picker's executable")
assert(command:find("--color 'border:#ebbcba'", 1, true), "explicit fzf override not passed")
io.popen, util.write_file, tmux.save_socket = original_popen, original_write_file, original_socket
io.write("color configuration tests passed\n")
