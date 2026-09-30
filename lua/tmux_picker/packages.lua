local config = require("tmux_picker.config")
local json = require("tmux_picker.json")
local util = require("tmux_picker.util")
local M = {}

function M.specs()
	if type(config.plugins) ~= "table" then error("plugins must be a list") end
	local specs, names = {}, {}
	local count = 0
	for key in pairs(config.plugins) do
		count = count + 1
		if type(key) ~= "number" then error("plugins must be a list") end
	end
	if count ~= #config.plugins then error("plugins must be a contiguous list") end
	for _, declaration in ipairs(config.plugins) do
		local spec = type(declaration) == "string" and {repo = declaration} or declaration
		if type(spec) ~= "table" or type(spec.repo) ~= "string" or spec.repo == "" then
			error("each plugin needs a repo")
		end
		local basename = spec.repo:gsub("/+$", ""):match("([^/:]+)$")
		local name = spec.name or (basename and basename:gsub("%.git$", ""))
		if type(name) ~= "string" or not name:match("^[%w][%w_.-]*$") then error("invalid plugin name") end
		if names[name] then error("duplicate plugin name: " .. name) end
		names[name] = true
		local entry = spec.entry or "plugin.lua"
		if type(entry) ~= "string" or entry:sub(1, 1) == "/" or not entry:match("%.lua$") then
			error("entry must be a relative .lua path: " .. name)
		end
		for part in entry:gmatch("[^/]+") do if part == ".." then error("entry cannot escape its repository") end end
		if spec.version ~= nil and (type(spec.version) ~= "string" or spec.version == "") then error("invalid version: " .. name) end
		if spec.enabled ~= nil and type(spec.enabled) ~= "boolean" then error("enabled must be boolean: " .. name) end
		specs[#specs + 1] = {name = name, repo = spec.repo, entry = entry, version = spec.version, enabled = spec.enabled ~= false}
	end
	return specs
end

function M.load(registry)
	local ok, specs = pcall(M.specs)
	if not ok then registry.report_error(tostring(specs)); return end
	if os.getenv("TMUX_PICKER_DISABLE_PLUGINS") == "1" then return end
	local index = json.read(config.managed_plugin_dir .. "/index.json") or {}
	for _, err in ipairs(index.errors or {}) do registry.report_error(err) end
	local installed = {}
	for _, package in ipairs(index.packages or {}) do installed[package.name] = package end
	for _, spec in ipairs(specs) do
		local package = installed[spec.name]
		if spec.enabled and package and package.repo == spec.repo and package.entry == spec.entry
			and (package.version or "") == (spec.version or "") then
			registry.load_plugin(config.managed_plugin_dir .. "/" .. spec.name .. "/" .. spec.entry)
		elseif spec.enabled then
			registry.report_error("plugin " .. spec.name .. " is not synchronized; reopen the picker to reconcile it")
		end
	end
end

function M.sync()
	if os.getenv("TMUX_PICKER_DISABLE_PLUGINS") == "1" then return end
	local ok, specs = pcall(M.specs)
	if not ok then return end -- Loading reports the configuration error.
	if #specs == 0 and not util.file_exists(config.managed_plugin_dir .. "/index.json") then return end
	local request = json.encode({specs = specs, directory = config.managed_plugin_dir,
		update_interval = config.plugins_update_interval})
	local command = "printf '%s' " .. util.shell_quote(request) .. " | PATH=" .. util.shell_quote(config.path_prefix)
		.. " python3 " .. util.shell_quote(config.root .. "/bin/tmux-picker-plugins")
	local response = json.decode(util.run(command) or "")
	if type(response) ~= "table" then
		io.stderr:write("tmux-picker: plugin sync unavailable; Python 3 and Git are required\n")
	elseif not response.ok then
		io.stderr:write("tmux-picker: ", response.error or "plugin sync failed", "\n")
	end
end

return M
