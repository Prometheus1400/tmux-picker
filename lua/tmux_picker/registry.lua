local config = require("tmux_picker.config")
local git = require("tmux_picker.git")
local json = require("tmux_picker.json")
local tmux = require("tmux_picker.tmux")
local util = require("tmux_picker.util")

local M = {}

local views = {}
local view_order = {}
local kinds = {}
local actions = {}
local decorators = {}
local supplements = {}
local hooks = {}
local plugins = {}
local errors = {}

local function copy_table(source)
	local output = {}
	for key, value in pairs(source) do
		output[key] = value
	end
	return output
end

local function copy_lists(source)
	local output = {}
	for key, values in pairs(source) do
		output[key] = copy_table(values)
	end
	return output
end

local function add_error(message)
	errors[#errors + 1] = message
	io.stderr:write("tmux-picker: ", message, "\n")
end

local function claim(store, id, value, label)
	if type(id) ~= "string" or id == "" then
		error(label .. " id is required")
	end
	if store[id] then
		error("duplicate " .. label .. " id: " .. id)
	end
	store[id] = value
end

function M.register_view(view)
	claim(views, view and view.id, view, "view")
	view.size = view.size or config.size
	view.preview_window = view.preview_window or config.preview_window
	view.keys = view.keys or {}
	view._registration_order = #view_order + 1
	view_order[#view_order + 1] = view.id
end

function M.register_kind(id, handler)
	claim(kinds, id, handler or {}, "kind")
end

function M.register_action(id, handler)
	claim(actions, id, handler, "action")
end

function M.register_decorator(scope, handler)
	decorators[scope] = decorators[scope] or {}
	decorators[scope][#decorators[scope] + 1] = handler
end

function M.register_supplement(view_id, handler)
	supplements[view_id] = supplements[view_id] or {}
	supplements[view_id][#supplements[view_id] + 1] = handler
end

function M.register_hook(event, handler)
	hooks[event] = hooks[event] or {}
	hooks[event][#hooks[event] + 1] = handler
end

function M.view(id)
	return views[id]
end

function M.views()
	local output = {}
	for _, id in ipairs(view_order) do
		output[#output + 1] = views[id]
	end
	table.sort(output, function(left, right)
		local left_order = left.order or 100
		local right_order = right.order or 100
		if left_order ~= right_order then
			return left_order < right_order
		end
		return left._registration_order < right._registration_order
	end)
	return output
end

function M.first_view()
	return M.views()[1]
end

function M.kind(id)
	return kinds[id]
end

function M.action(id)
	return actions[id]
end

function M.decorate(scope, value, data)
	for _, handler in ipairs(decorators[scope] or {}) do
		local ok, result = pcall(handler, value, data or {})
		if ok and result ~= nil then
			value = result
		elseif not ok then
			add_error("decorator " .. scope .. " failed: " .. tostring(result))
		end
	end
	return value
end

function M.emit_supplements(view_id, context)
	for _, handler in ipairs(supplements[view_id] or {}) do
		local ok, err = pcall(handler, context)
		if not ok then
			add_error("supplement " .. view_id .. " failed: " .. tostring(err))
		end
	end
end

function M.run_hooks(event, ...)
	local result
	for _, handler in ipairs(hooks[event] or {}) do
		local ok, value = pcall(handler, ...)
		if not ok then
			add_error("hook " .. event .. " failed: " .. tostring(value))
		elseif value ~= nil then
			result = value
		end
	end
	return result
end

function M.context(plugin_id)
	return {
		plugin_id = plugin_id,
		config = config,
		util = util,
		tmux = tmux,
		git = git,
		json = json,
		emit = util.emit,
		notify = util.notify,
		register_view = M.register_view,
		register_kind = M.register_kind,
		register_action = M.register_action,
		register_decorator = M.register_decorator,
		register_supplement = M.register_supplement,
		register_hook = M.register_hook,
		decorate = M.decorate,
	}
end

function M.load_plugin(path)
	local ok, plugin = pcall(dofile, path)
	if not ok then
		add_error(path .. ": " .. tostring(plugin))
		return false
	end
	if type(plugin) ~= "table" then
		add_error(path .. ": plugin must return a table")
		return false
	end
	if plugin.api_version ~= config.api_version then
		add_error(path .. ": unsupported api_version " .. tostring(plugin.api_version))
		return false
	end
	if type(plugin.id) ~= "string" or plugin.id == "" then
		add_error(path .. ": plugin id is required")
		return false
	end
	if plugins[plugin.id] then
		add_error(path .. ": duplicate plugin id " .. plugin.id)
		return false
	end
	if type(plugin.setup) ~= "function" then
		add_error(path .. ": setup(ctx) is required")
		return false
	end
	local plugin_id = plugin.id
	local before = {
		views = views,
		view_order = view_order,
		kinds = kinds,
		actions = actions,
		decorators = decorators,
		supplements = supplements,
		hooks = hooks,
	}
	views = copy_table(views)
	view_order = copy_table(view_order)
	kinds = copy_table(kinds)
	actions = copy_table(actions)
	decorators = copy_lists(decorators)
	supplements = copy_lists(supplements)
	hooks = copy_lists(hooks)
	local setup_error
	ok, setup_error = pcall(plugin.setup, M.context(plugin_id))
	if not ok then
		views = before.views
		view_order = before.view_order
		kinds = before.kinds
		actions = before.actions
		decorators = before.decorators
		supplements = before.supplements
		hooks = before.hooks
		add_error(path .. ": setup failed: " .. tostring(setup_error))
		return false
	end
	plugins[plugin_id] = path
	return true
end

function M.load_plugins(directory)
	if os.getenv("TMUX_PICKER_DISABLE_PLUGINS") == "1" or not util.is_dir(directory) then
		return
	end
	local command = "ls -1 " .. util.shell_quote(directory) .. "/*.lua 2>/dev/null"
	local paths = util.lines(command)
	table.sort(paths)
	for _, path in ipairs(paths) do
		M.load_plugin(path)
	end
end

function M.errors()
	return errors
end

function M.reset()
	views, view_order, kinds, actions = {}, {}, {}, {}
	decorators, supplements, hooks, plugins, errors = {}, {}, {}, {}, {}
end

return M
