local config = require("tmux_picker.config")
local util = require("tmux_picker.util")

local M = {}

-- tmux's saved layout describes the full split tree even while a pane is zoomed.
function M.parse(layout)
	local text = tostring(layout or ""):match("^[%x]+,(.+)$")
	if not text then
		return nil
	end
	local position = 1
	local function node()
		local width, height, _, _, next_position =
			text:sub(position):match("^(%d+)x(%d+),(%d+),(%d+)()")
		if not width or tonumber(width) < 1 or tonumber(height) < 1 then
			return nil
		end
		position = position + next_position - 1
		local result = { width = tonumber(width), height = tonumber(height) }
		local delimiter = text:sub(position, position)
		if delimiter == "{" or delimiter == "[" then
			result.axis = delimiter == "{" and "horizontal" or "vertical"
			result.children = {}
			local closing = delimiter == "{" and "}" or "]"
			position = position + 1
			while true do
				local child = node()
				if not child then
					return nil
				end
				result.children[#result.children + 1] = child
				local separator = text:sub(position, position)
				position = position + 1
				if separator == closing then
					break
				elseif separator ~= "," then
					return nil
				end
			end
		elseif delimiter == "," then
			local id, ending = text:sub(position + 1):match("^(%d+)()")
			if not id then
				return nil
			end
			result.id = "%" .. id
			position = position + ending
		else
			return nil
		end
		return result
	end
	local tree = node()
	if not tree or position <= #text then
		return nil
	end
	return tree
end

local function measure(node)
	if not node.children then
		node.min_width, node.min_height = 4, 2 -- spans between shared borders
		return
	end
	local width, height = 0, 0
	for _, child in ipairs(node.children) do
		measure(child)
		if node.axis == "horizontal" then
			width = width + child.min_width
			height = math.max(height, child.min_height)
		else
			width = math.max(width, child.min_width)
			height = height + child.min_height
		end
	end
	node.min_width, node.min_height = width, height
end

local function plain(value)
	return util.clean_field(value):gsub("\27%[[0-9;]*m", ""):gsub("[%z\1-\31\127]", "")
end

local function clipped(value, width)
	local characters = {}
	for character in plain(value):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		characters[#characters + 1] = character
	end
	if #characters <= width then
		return table.concat(characters), #characters
	end
	return table.concat(characters, "", 1, math.max(0, width - 1)) .. "…", width
end

local glyphs = {
	[1] = "│",
	[2] = "─",
	[3] = "└",
	[4] = "│",
	[5] = "│",
	[6] = "┌",
	[7] = "├",
	[8] = "─",
	[9] = "┘",
	[10] = "─",
	[11] = "┴",
	[12] = "┐",
	[13] = "┤",
	[14] = "┬",
	[15] = "┼",
}

function M.render(layout, panes, columns, lines)
	local tree = M.parse(layout)
	if not tree then
		return nil
	end
	columns = math.max(1, math.floor(tonumber(columns) or 80))
	lines = math.max(1, math.floor(tonumber(lines) or 16))
	measure(tree)
	if columns - 1 < tree.min_width or lines - 1 < tree.min_height then
		return nil -- the existing pane details remain readable in tiny previews
	end
	local by_id = {}
	for _, pane in ipairs(panes) do
		by_id[pane.id] = pane
	end
	local grid = {}
	for y = 1, lines do
		grid[y] = {}
	end
	local function edge(x, y, direction)
		local cell = grid[y][x] or 0
		if math.floor(cell / direction) % 2 == 0 then
			grid[y][x] = cell + direction
		end
	end
	local function box(left, top, right, bottom)
		for x = left, right - 1 do
			edge(x, top, 2)
			edge(x + 1, top, 8)
			edge(x, bottom, 2)
			edge(x + 1, bottom, 8)
		end
		for y = top, bottom - 1 do
			edge(left, y, 4)
			edge(left, y + 1, 1)
			edge(right, y, 4)
			edge(right, y + 1, 1)
		end
	end
	local function label(value, left, right, y, active)
		local text, width = clipped(value, right - left - 1)
		local x = left + 1 + math.floor((right - left - 1 - width) / 2)
		for character in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			grid[y][x] = { character = character, active = active }
			x = x + 1
		end
	end
	local function draw(node, left, top, right, bottom)
		if not node.children then
			box(left, top, right, bottom)
			local pane = by_id[node.id] or { index = node.id, command = "unavailable" }
			local active = pane.active == "1"
			local index = tostring(pane.index or node.id) .. (active and " *" or "")
			local middle = top + math.floor((bottom - top) / 2)
			if bottom - top >= 3 then
				label("pane " .. index, left, right, middle, active)
				label(pane.command, left, right, middle + 1, active)
			else
				label(index .. " " .. (pane.command or ""), left, right, middle, active)
			end
			return
		end
		local horizontal = node.axis == "horizontal"
		local span = horizontal and (right - left) or (bottom - top)
		local minimum, weight = 0, 0
		for _, child in ipairs(node.children) do
			minimum = minimum + (horizontal and child.min_width or child.min_height)
			weight = weight + (horizontal and child.width or child.height)
		end
		local offset, accumulated, extra_used = 0, 0, 0
		for _, child in ipairs(node.children) do
			accumulated = accumulated + (horizontal and child.width or child.height)
			local extra = math.floor((span - minimum) * accumulated / weight + 0.5)
			local size = (horizontal and child.min_width or child.min_height) + extra - extra_used
			if horizontal then
				draw(child, left + offset, top, left + offset + size, bottom)
			else
				draw(child, left, top + offset, right, top + offset + size)
			end
			offset, extra_used = offset + size, extra
		end
	end
	draw(tree, 1, 1, columns, lines)
	local output = {}
	for _, row in ipairs(grid) do
		local cells = {}
		local colored = false
		for x = 1, columns do
			local cell = row[x]
			local active = type(cell) == "table" and cell.active or false
			if active ~= colored then
				cells[#cells + 1] = active and config.colors.green or config.colors.reset
				colored = active
			end
			cells[#cells + 1] = type(cell) == "table" and cell.character
				or type(cell) == "number" and glyphs[cell] or " "
		end
		if colored then
			cells[#cells + 1] = config.colors.reset
		end
		output[#output + 1] = table.concat(cells)
	end
	return table.concat(output, "\n")
end

return M
