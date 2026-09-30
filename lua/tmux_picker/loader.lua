local config = require("tmux_picker.config")
local registry = require("tmux_picker.registry")
local util = require("tmux_picker.util")

local M = {}

local function merge(target, source)
	for key, value in pairs(source or {}) do
		if type(value) == "table" and type(target[key]) == "table" then
			for child_key, child_value in pairs(value) do
				target[key][child_key] = child_value
			end
		else
			target[key] = value
		end
	end
end

function M.configure()
	local path = config.config_home .. "/tmux-picker/init.lua"
	if not util.file_exists(path) then
		return
	end
	local ok, options = pcall(dofile, path)
	if not ok then
		io.stderr:write("tmux-picker: ", path, ": ", tostring(options), "\n")
	elseif type(options) == "table" then
		merge(config, options)
	else
		io.stderr:write("tmux-picker: ", path, " must return a table\n")
	end
end

function M.plugins()
	registry.load_plugins(config.plugin_dir)
end

return M
