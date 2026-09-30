local config = require("tmux_picker.config")

local M = {}
local unpack_values = table.unpack or unpack

function M.shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function M.notify(message)
	os.execute(
		"PATH="
			.. M.shell_quote(config.path_prefix)
			.. " tmux display-message "
			.. M.shell_quote("tmux-picker: " .. tostring(message))
			.. " 2>/dev/null"
	)
end

function M.die(message)
	M.notify(message)
	io.stderr:write("tmux-picker: ", tostring(message), "\n")
	os.exit(1)
end

function M.need(command)
	local handle = io.popen(
		"PATH=" .. M.shell_quote(config.path_prefix) .. " command -v " .. M.shell_quote(command) .. " 2>/dev/null"
	)
	local output = handle and handle:read("*a") or ""
	if handle then
		handle:close()
	end
	if output == "" then
		M.die(command .. " not found")
	end
end

function M.run(command)
	local handle = io.popen(command)
	if not handle then
		return nil
	end
	local output = handle:read("*a")
	local ok = handle:close()
	if not ok then
		return nil
	end
	return output
end

function M.lines(command)
	local output = M.run(command)
	local rows = {}
	for line in (output or ""):gmatch("[^\n]+") do
		rows[#rows + 1] = line
	end
	return rows
end

function M.trim(value)
	local trimmed = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
	return trimmed
end

function M.read_file(path)
	local handle = io.open(path, "r")
	if not handle then
		return nil
	end
	local data = handle:read("*a")
	handle:close()
	return data
end

function M.write_file(path, data)
	local handle = io.open(path, "w")
	if not handle then
		return false
	end
	handle:write(data)
	handle:close()
	return true
end

function M.file_exists(path)
	local handle = io.open(path, "r")
	if not handle then
		return false
	end
	handle:close()
	return true
end

function M.is_dir(path)
	if not path or path == "" then
		return false
	end
	local ok = os.execute("test -d " .. M.shell_quote(path))
	return ok == true or ok == 0
end

function M.split_tab(line, max_fields)
	local fields = {}
	local start = 1
	local limit = max_fields and math.max(1, max_fields - 1) or math.huge
	while #fields < limit do
		local finish = line:find("\t", start, true)
		if not finish then
			break
		end
		fields[#fields + 1] = line:sub(start, finish - 1)
		start = finish + 1
	end
	fields[#fields + 1] = line:sub(start)
	return unpack_values(fields)
end

function M.clean_field(value)
	local cleaned = tostring(value or ""):gsub("[\r\n\t]", " ")
	return cleaned
end

function M.visible_width(value)
	value = tostring(value or ""):gsub("\27%[[0-9;]*m", "")
	local width = 0
	for _ in value:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		width = width + 1
	end
	return width
end

function M.pad_visible(value, width)
	value = tostring(value or "")
	local missing = (tonumber(width) or 0) - M.visible_width(value)
	return missing > 0 and (value .. string.rep(" ", missing)) or value
end

function M.emit(row)
	io.write(
		table.concat({
			M.clean_field(row.kind),
			M.clean_field(row.target),
			M.clean_field(row.name),
			M.clean_field(row.source),
			M.clean_field(row.extra),
		}, config.tab),
		"\n"
	)
end

function M.row(line)
	local kind, target, name, source, extra = M.split_tab(line or "", 5)
	return {
		kind = kind or "",
		target = target or "",
		name = name or "",
		source = source or "",
		extra = extra or "",
		raw = line or "",
	}
end

function M.basename(path)
	return tostring(path or ""):match("([^/]+)/?$")
end

return M
