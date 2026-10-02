local config = require("tmux_picker.config")
local loader = require("tmux_picker.loader")
local picker = require("tmux_picker.picker")
local registry = require("tmux_picker.registry")
local tmux = require("tmux_picker.tmux")
local util = require("tmux_picker.util")
local views = require("tmux_picker.views")
local root = assert(os.getenv("TMUX_PICKER_ROOT"))
config.plugin_dir = root .. "/tests/fixtures/missing"
config.managed_plugin_dir = root .. "/tests/fixtures/missing"
local function reload(options)
	config.bundled_plugins = options
	registry.reset()
	views.register_kinds()
	loader.plugins()
	assert(#registry.errors() == 0)
end
reload({ zoxide = false, agents = false })
assert(#registry.views() == 3 and registry.first_view().id == "sessions")
for _, id in ipairs({ "sessions", "windows", "panes" }) do
	reload({ [id] = false, zoxide = false, agents = false })
	assert(not registry.view(id) and #registry.views() == 2)
	assert(picker.switch_action(id, "picker") == "ignore")
	assert(not picker.legend(registry.first_view().id):find(views.definition(id).chord, 1, true))
	reload({ [id] = true, zoxide = false, agents = false })
	assert(registry.view(id) and #registry.views() == 3)
end
reload({ sessions = false, panes = false, zoxide = false, agents = false })
assert(registry.first_view().id == "windows")
local original_popen, original_write, original_socket = io.popen, util.write_file, tmux.save_socket
local command
io.popen = function(value)
	command = value
	return { read = function() return "" end, close = function() return true end }
end
util.write_file = function() end
tmux.save_socket = function() end
picker.open("sessions", "picker")
assert(command:find("list 'windows'", 1, true))
assert(not command:find("ctrl-t:transform", 1, true) and not command:find("ctrl-o:transform", 1, true))
io.popen, util.write_file, tmux.save_socket = original_popen, original_write, original_socket
reload(false)
assert(#registry.views() == 0)
assert(registry.kind("session").accept and registry.kind("pane").preview)
config.plugin_dir = root .. "/tests/fixtures"
reload(false)
assert(#registry.views() == 1 and registry.first_view().id == "example")
-- zoxide still uses core session handlers with its Sessions view disabled.
config.plugin_dir = root .. "/tests/fixtures/missing"
local original_run = util.run
util.run = function(command)
	if command:find("command -v zoxide", 1, true) then return "/fake/zoxide" end
	return original_run(command)
end
reload({})
local expected = { "sessions", "zoxide", "windows", "agents", "panes" }
for index, view in ipairs(registry.views()) do assert(view.id == expected[index]) end
assert(#registry.views() == #expected)
reload({ sessions = false, windows = false, panes = false, agents = false })
util.run = original_run
assert(registry.first_view().id == "zoxide")
local original_ensure, original_switch = tmux.ensure_session, tmux.switch_session
local ensured, switched
tmux.ensure_session = function(name, path) ensured = { name, path } end
tmux.switch_session = function(name) switched = name end
registry.kind("session").accept({ target = "/tmp", source = "zoxide" })
tmux.ensure_session, tmux.switch_session = original_ensure, original_switch
assert(ensured[1] == "tmp" and ensured[2] == "/tmp" and switched == "tmp")
io.write("bundled view tests passed\n")
