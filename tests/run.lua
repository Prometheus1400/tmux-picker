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
views.register()
equal(registry.first_view().id, "sessions", "default view")
equal(#registry.views(), 4, "core view count")
assert(registry.kind("session").accept, "session accept handler")
assert(registry.kind("pane").preview, "pane preview handler")

local row = util.row("session\twork\tWork tree\ttmux\t main")
equal(row.kind, "session", "row kind")
equal(row.target, "work", "row target")
equal(row.source, "tmux", "row source")
equal(row.extra, " main", "row extra")

registry.load_plugins(root .. "/tests/fixtures")
equal(#registry.views(), 5, "plugin view count")
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

io.write("tmux-picker tests passed\n")
