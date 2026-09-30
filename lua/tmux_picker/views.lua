local config = require("tmux_picker.config")
local git = require("tmux_picker.git")
local registry = require("tmux_picker.registry")
local sessions = require("tmux_picker.sessions")
local tmux = require("tmux_picker.tmux")
local util = require("tmux_picker.util")

local M = {}

local function window_location(session, index, name)
	local location = session .. ":" .. index
	if name and name ~= "" and name ~= "Window" and name ~= index then
		location = location .. "/" .. name
	end
	return location
end

local function pane_location(session, name)
	if not name or name == "" or name == "Window" then
		return session
	end
	return session .. "/" .. name
end

local function list_sessions()
	sessions.list_tmux()
	registry.emit_supplements("sessions", {
		emit = util.emit,
		allowed_sessions = sessions.allowed(),
	})
end

local function list_windows()
	local allowed = sessions.allowed()
	for _, line in
		ipairs(
			tmux.list_windows_all(
				"#{session_name}\t#{window_id}\t#{window_index}\t" .. "#{window_name}\t#{pane_current_path}"
			)
		)
	do
		local session, id, index, name, path = util.split_tab(line, 5)
		if session and id and allowed[session] then
			local display = config.colors.teal
				.. config.icons.window
				.. "\27[39m "
				.. window_location(session, index, name)
			display = registry.decorate("window", display, {
				session = session,
				id = id,
				index = index,
				name = name,
				path = path,
			})
			util.emit({
				kind = "window",
				target = id,
				name = display,
				extra = git.decorate(git.ref(path)),
			})
		end
	end
	registry.emit_supplements("windows", { emit = util.emit })
end

local function list_panes()
	local allowed = sessions.allowed()
	for _, line in
		ipairs(
			tmux.list_panes(
				"#{session_name}\t#{pane_id}\t#{window_name}\t" .. "#{pane_current_command}\t#{pane_current_path}"
			)
		)
	do
		local session, id, window, command, path = util.split_tab(line, 5)
		if session and id and allowed[session] then
			command = registry.decorate("command", command or "", {
				session = session,
				pane_id = id,
				path = path,
			})
			local display = config.colors.yellow
				.. config.icons.pane
				.. "\27[39m "
				.. pane_location(session, window)
				.. "  "
				.. command
			display = registry.decorate("pane", display, {
				session = session,
				pane_id = id,
				window = window,
				command = command,
				path = path,
			})
			util.emit({
				kind = "pane",
				target = id,
				name = display,
				extra = git.decorate(git.ref(path)),
			})
		end
	end
	registry.emit_supplements("panes", { emit = util.emit })
end

local function preview_path(path)
	if not path or path == "" then
		return
	end
	io.write(config.colors.muted, path, config.colors.reset, "\n")
	local ref = git.ref(path)
	if ref then
		io.write(config.colors.muted, config.icons.git, " ", ref, config.colors.reset, "\n")
	end
end

local function preview_session(session, source)
	if source and source ~= "" and source ~= "tmux" then
		preview_path(session)
		return
	end
	io.write(config.colors.muted, session, config.colors.reset, "\n")
	for _, line in ipairs(tmux.list_windows(session, "#{window_index}\t#{window_name}\t#{window_active}")) do
		local index, name, active = util.split_tab(line, 3)
		local marker = active == "1" and (config.colors.green .. "●" .. config.colors.reset) or "○"
		io.write(
			"\n",
			marker,
			" ",
			config.colors.green,
			"window ",
			index or "",
			config.colors.reset,
			"  ",
			name or "",
			"\n"
		)
		for _, pane_line in
			ipairs(
				tmux.list_window_panes(
					session .. ":" .. tostring(index),
					"#{pane_index}\t#{pane_id}\t#{pane_current_command}\t"
						.. "#{pane_width}x#{pane_height}\t#{pane_current_path}\t#{pane_active}"
				)
			)
		do
			local pane, id, command, size, path, pane_active = util.split_tab(pane_line, 6)
			command = registry.decorate("command", command or "", {
				session = session,
				pane_id = id,
				path = path,
			})
			local pane_marker = pane_active == "1" and (config.colors.green .. "▸" .. config.colors.reset) or " "
			local ref = git.ref(path)
			io.write(
				"  ",
				pane_marker,
				" ",
				config.colors.muted,
				"pane ",
				pane or "",
				config.colors.reset,
				"  ",
				command,
				"  ",
				size or "",
				"\n    ",
				path or "",
				ref and git.decorate(ref) or "",
				"\n"
			)
		end
	end
end

local function tail_lines(text, count)
	local rows = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		rows[#rows + 1] = line
	end
	while #rows > count do
		table.remove(rows, 1)
	end
	while #rows > 1 and rows[#rows]:match("^%s*$") do
		table.remove(rows)
	end
	return table.concat(rows, "\n")
end

local function preview_pane(id)
	local info = tmux.info(
		id,
		"#{session_name}\t#{window_index}\t#{window_name}\t#{pane_index}\t"
			.. "#{pane_title}\t#{pane_current_command}\t#{pane_width}x#{pane_height}\t"
			.. "#{pane_current_path}\t#{pane_active}"
	)
	if not info then
		io.write(config.colors.peach, "pane unavailable", config.colors.reset, "\n")
		return
	end
	local session, window_index, window_name, pane_index, title, command, size, path, active = util.split_tab(info, 9)
	local location = window_location(session, window_index, window_name) .. "  pane " .. (pane_index or "")
	local marker = active == "1" and (config.colors.green .. "●" .. config.colors.reset) or "○"
	command = registry.decorate("command", command or "", {
		session = session,
		pane_id = id,
		path = path,
	})
	io.write(marker, " ", config.colors.green, location, config.colors.reset, "\n")
	io.write(config.colors.muted, command, config.colors.reset, "  ", size or "", "\n")
	if title and title ~= "" and title ~= command then
		io.write("title  ", title, "\n")
	end
	if path and path ~= "" then
		io.write("path   ", path, git.decorate(git.ref(path)), "\n")
	end
	local capture = tmux.capture_pane(id, -120)
	if capture and capture ~= "" then
		local lines = math.max(1, math.floor(tonumber(os.getenv("FZF_PREVIEW_LINES")) or 24) - 7)
		io.write("\n", tail_lines(capture, lines), "\n")
	end
end

local function preview_window(id)
	local info = tmux.info(id, "#{session_name}\t#{window_index}\t#{window_name}\t#{window_active}")
	if not info then
		io.write(config.colors.peach, "window unavailable", config.colors.reset, "\n")
		return
	end
	local session, index, name, active = util.split_tab(info, 4)
	local marker = active == "1" and (config.colors.green .. "●" .. config.colors.reset) or "○"
	io.write(marker, " ", config.colors.green, window_location(session, index, name), config.colors.reset, "\n")
	for _, line in
		ipairs(
			tmux.list_window_panes(
				id,
				"#{pane_index}\t#{pane_id}\t#{pane_active}\t#{pane_current_command}\t"
					.. "#{pane_width}x#{pane_height}\t#{pane_current_path}"
			)
		)
	do
		local pane, pane_id, pane_active, command, size, path = util.split_tab(line, 6)
		command = registry.decorate("command", command or "", {
			session = session,
			pane_id = pane_id,
			path = path,
		})
		local pane_marker = pane_active == "1" and (config.colors.green .. "▸" .. config.colors.reset) or " "
		io.write(
			"\n  ",
			pane_marker,
			" pane ",
			pane or "",
			"  ",
			command,
			"  ",
			size or "",
			"\n    ",
			path or "",
			git.decorate(git.ref(path)),
			"\n"
		)
	end
end

function M.register()
	registry.register_kind("session", {
		accept = function(row)
			sessions.connect(row.target)
		end,
		preview = function(row)
			preview_session(row.target, row.source)
		end,
	})
	registry.register_kind("window", {
		accept = function(row)
			tmux.switch_window(row.target)
		end,
		preview = function(row)
			preview_window(row.target)
		end,
	})
	registry.register_kind("pane", {
		accept = function(row)
			tmux.switch_pane(row.target)
		end,
		preview = function(row)
			preview_pane(row.target)
		end,
	})

	registry.register_view({
		id = "sessions",
		order = 10,
		label = "tmux",
		key = "ctrl-t",
		chord = "C-t",
		prompt = config.icons.session .. "  ",
		list = list_sessions,
		query = sessions.connect,
	})
	registry.register_view({
		id = "windows",
		order = 40,
		label = "windows",
		key = "ctrl-w",
		chord = "C-w",
		prompt = config.icons.window .. "  ",
		list = list_windows,
	})
	registry.register_view({
		id = "panes",
		order = 50,
		label = "panes",
		key = "ctrl-o",
		chord = "C-o",
		prompt = config.icons.pane .. "  ",
		list = list_panes,
	})
end

return M
