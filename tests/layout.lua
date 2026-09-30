local layout = require("tmux_picker.layout")
local util = require("tmux_picker.util")
local registry = require("tmux_picker.registry")
local views = require("tmux_picker.views")
local tmux = require("tmux_picker.tmux")
local git = require("tmux_picker.git")

local panes = {
	{ id = "%1", index = "0", command = "nvim", active = "1" },
	{ id = "%2", index = "1", command = "zsh" },
	{ id = "%3", index = "2", command = "python" },
}
local single = "0000,80x24,0,0,1"
local horizontal = "0000,80x24,0,0{39x24,0,0,1,40x24,40,0,2}"
local vertical = "0000,80x24,0,0[80x11,0,0,1,80x12,0,12,2]"
local nested = "0000,80x24,0,0{39x24,0,0,1,40x24,40,0[40x11,40,0,2,40x12,40,12,3]}"

local function plain(text)
	return text:gsub("\27%[[0-9;]*m", "")
end

local function diagram(description, width, height)
	local rendered = assert(layout.render(description, panes, width, height))
	local count = 0
	for row in rendered:gmatch("[^\n]+") do
		assert(util.visible_width(row) == width, "diagram exceeds preview width")
		count = count + 1
	end
	assert(count == height, "diagram exceeds preview height")
	return plain(rendered)
end

local one = diagram(single, 30, 7)
assert(one:find("pane 0 *", 1, true) and one:find("nvim", 1, true))
local side_by_side = diagram(horizontal, 40, 9)
assert(side_by_side:find("┬", 1, true) and side_by_side:find("┴", 1, true))
assert(side_by_side:find("nvim", 1, true) and side_by_side:find("zsh", 1, true))
local stacked = diagram(vertical, 40, 9)
assert(stacked:find("├", 1, true) and stacked:find("┤", 1, true))
local mixed = diagram(nested, 60, 12)
assert(mixed:find("nvim", 1, true) and mixed:find("zsh", 1, true) and mixed:find("python", 1, true))
assert(mixed:find("├", 1, true), "nested split junction missing")
assert(layout.render(nested, panes, 4, 2) == nil, "tiny preview should fall back")
for _, malformed in ipairs({ "", "invalid", "0000,80x24,0,0", horizontal .. "junk", "0000,80x24,0,0{broken}" }) do
	assert(layout.parse(malformed) == nil, "invalid layout accepted")
end
local missing = plain(assert(layout.render(single, {}, 30, 5)))
assert(missing:find("unavailable", 1, true), "closed pane lacks a fallback label")
panes[1].command = "\27[31mvery-long-process-name\27[0m"
local shortened = diagram(single, 12, 5)
assert(shortened:find("…", 1, true), "long label should be truncated")
panes[1].command = "café"
assert(diagram(single, 20, 5):find("café", 1, true), "UTF-8 process name corrupted")

-- The window preview must use the saved layout when pane geometry is zoomed.
registry.reset()
views.register()
local original_info, original_panes, original_ref, original_write = tmux.info, tmux.list_window_panes, git.ref, io.write
local output = {}
tmux.info = function()
	return "work\t1\tWindow\t1\t" .. horizontal .. "\t1"
end
tmux.list_window_panes = function()
	return {
		"0\t%1\t1\tnvim\t80x24\t/tmp",
		"1\t%2\t0\tlong-process-name\t40x24\t/tmp",
	}
end
git.ref = function() return nil end
io.write = function(...)
	for index = 1, select("#", ...) do
		output[#output + 1] = tostring(select(index, ...))
	end
end
registry.kind("window").preview({ target = "@1" })
io.write = original_write
tmux.info, tmux.list_window_panes, git.ref = original_info, original_panes, original_ref
local preview = plain(table.concat(output))
assert(preview:find("(zoomed)", 1, true), "zoomed state missing")
assert(preview:find("┬", 1, true), "zoomed preview lost the saved split layout")
assert(preview:find("long-process-name", 1, true), "full process name missing from pane details")

io.write("window layout tests passed\n")
