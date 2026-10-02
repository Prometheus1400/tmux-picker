local registry = require("tmux_picker.registry")
local util = require("tmux_picker.util")
local views = require("tmux_picker.views")

local function equal(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)))
	end
end

local root = assert(os.getenv("TMUX_PICKER_ROOT"), "TMUX_PICKER_ROOT missing")

registry.reset()
views.register_kinds()
for _, name in ipairs({ "sessions", "windows", "panes" }) do
	assert(registry.load_plugin(root .. "/plugins/" .. name .. ".lua"))
end
equal(registry.first_view().id, "sessions", "default view")
equal(#registry.views(), 3, "bundled tmux view count")
assert(registry.kind("session").accept, "session accept handler")
assert(registry.kind("pane").preview, "pane preview handler")

local row = util.row("session\twork\tWork tree\ttmux\t main")
equal(row.kind, "session", "row kind")
equal(row.target, "work", "row target")
equal(row.source, "tmux", "row source")
equal(row.extra, " main", "row extra")

registry.load_plugins(root .. "/tests/fixtures")
equal(#registry.views(), 4, "plugin view count")
assert(registry.kind("example"), "plugin kind")
assert(registry.action("example.reload"), "plugin action")
equal(registry.decorate("session", "base", {}), "base decorated", "decorator")
local context = {}
registry.emit_supplements("sessions", context)
assert(context.seen, "supplement did not run")

local invalid = os.tmpname()
local handle = assert(io.open(invalid, "w"))
handle:write([[
return {
  api_version = 1,
  id = "broken",
  setup = function(ctx)
    ctx.register_view({ id = "partial", prompt = "> ", list = function() end })
    error("expected failure")
  end,
}
]])
handle:close()
assert(not registry.load_plugin(invalid), "broken plugin unexpectedly loaded")
os.remove(invalid)
assert(not registry.view("partial"), "failed plugin was not rolled back")

registry.reset()
views.register_kinds()
-- Use the test PATH consistently for optional-dependency checks.
require("tmux_picker.config").path_prefix = os.getenv("PATH") or "/usr/bin"
registry.load_plugins(root .. "/plugins")
local has_zoxide = util.run("command -v zoxide 2>/dev/null")
equal(registry.view("zoxide") ~= nil, has_zoxide ~= nil and has_zoxide ~= "", "bundled zoxide plugin")

local config = require("tmux_picker.config")
local loader = require("tmux_picker.loader")
local original_bundled_dir = config.bundled_plugin_dir
local original_plugin_dir = config.plugin_dir
local original_bundled_plugins = config.bundled_plugins
config.bundled_plugin_dir = root .. "/tests/fixtures"
config.plugin_dir = root .. "/tests/fixtures/missing"

local function reload_plugins()
	registry.reset()
	views.register_kinds()
	loader.plugins()
end

config.bundled_plugins = { example = false }
reload_plugins()
assert(not registry.view("example"), "disabled bundled plugin loaded")
equal(#registry.views(), 0, "disabled fixture plugin")

config.bundled_plugins.example = true
reload_plugins()
assert(registry.view("example"), "explicitly enabled bundled plugin missing")

config.bundled_plugins = {}
reload_plugins()
assert(registry.view("example"), "omitted bundled plugin should remain enabled")

config.bundled_plugins = false
reload_plugins()
equal(#registry.views(), 0, "all bundled plugins disabled")
config.plugin_dir = root .. "/tests/fixtures"
reload_plugins()
assert(registry.view("example"), "disabling bundled plugins disabled user plugins")

config.bundled_plugin_dir = root .. "/tests/fixtures/disabled"
config.bundled_plugins = { dangerous = false }
reload_plugins()
equal(#registry.errors(), 0, "disabled module must not be evaluated")

config.bundled_plugin_dir = original_bundled_dir
config.plugin_dir = original_plugin_dir
config.bundled_plugins = original_bundled_plugins

io.write("tmux-picker tests passed\n")
