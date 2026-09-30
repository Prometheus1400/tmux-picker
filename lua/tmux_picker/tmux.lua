local config = require("tmux_picker.config")
local util = require("tmux_picker.util")

local M = {}

local function sock_command()
	local socket = util.read_file(config.tmux_sock_file)
	socket = socket and socket:gsub("\n$", "")
	local command = "PATH=" .. util.shell_quote(config.path_prefix) .. " tmux"
	if socket and socket ~= "" then
		command = command .. " -S " .. util.shell_quote(socket)
	end
	return command
end

function M.command(arguments)
	return sock_command() .. " " .. arguments
end

function M.run(arguments)
	return util.run(M.command(arguments))
end

function M.save_socket()
	local socket = (os.getenv("TMUX") or ""):match("^([^,]+)")
	if socket then
		util.write_file(config.tmux_sock_file, socket .. "\n")
	end
end

function M.has_session(name)
	if not name or name == "" then
		return false
	end
	local ok = os.execute(M.command("has-session -t=" .. util.shell_quote(name) .. " >/dev/null 2>&1"))
	return ok == true or ok == 0
end

function M.ensure_session(name, path)
	if M.has_session(name) then
		return
	end
	local command = "new-session -ds " .. util.shell_quote(name)
	if path and path ~= "" then
		command = command .. " -c " .. util.shell_quote(path)
	end
	os.execute(M.command(command))
end

function M.switch_session(name)
	os.execute(M.command("switch-client -t=" .. util.shell_quote(name)))
end

function M.switch_window(target)
	local info = M.run(
		"display-message -p -t " .. util.shell_quote(target) .. " " .. util.shell_quote("#{session_name}\t#{window_id}")
	)
	local session, window = util.split_tab(util.trim(info), 2)
	if not session or not window then
		util.die("window " .. tostring(target) .. " is gone")
	end
	os.execute(M.command("switch-client -t " .. util.shell_quote(session)))
	os.execute(M.command("select-window -t " .. util.shell_quote(window)))
end

function M.switch_pane(target)
	local info = M.run(
		"display-message -p -t " .. util.shell_quote(target) .. " " .. util.shell_quote("#{session_name}\t#{window_id}")
	)
	local session, window = util.split_tab(util.trim(info), 2)
	if not session or not window then
		util.die("pane " .. tostring(target) .. " is gone")
	end
	os.execute(M.command("switch-client -t " .. util.shell_quote(session)))
	os.execute(M.command("select-window -t " .. util.shell_quote(window)))
	os.execute(M.command("select-pane -t " .. util.shell_quote(target)))
end

function M.kill(kind, target)
	local commands = {
		pane = "kill-pane",
		window = "kill-window",
		session = "kill-session",
	}
	local command = commands[kind]
	if command then
		os.execute(M.command(command .. " -t=" .. util.shell_quote(target)))
	end
end

function M.send_keys(pane, ...)
	local parts = { "send-keys", "-t", pane }
	for index = 1, select("#", ...) do
		parts[#parts + 1] = select(index, ...)
	end
	for index, part in ipairs(parts) do
		parts[index] = util.shell_quote(part)
	end
	local ok = os.execute(M.command(table.concat(parts, " ")))
	return ok == true or ok == 0
end

function M.pane_pid(pane)
	local output = M.run("display-message -p -t " .. util.shell_quote(pane) .. " '#{pane_pid}'")
	return output and util.trim(output)
end

function M.pane_owns_pid(pane, pid)
	local owner = M.pane_pid(pane)
	local current = tostring(pid or "")
	if not owner or not current:match("^%d+$") then
		return false
	end
	for _ = 1, 8 do
		if current == owner then
			return true
		end
		local parent = util.run("ps -o ppid= -p " .. util.shell_quote(current) .. " 2>/dev/null")
		current = parent and util.trim(parent) or ""
		if current == "" or current == "1" then
			break
		end
	end
	return false
end

function M.list_session_paths()
	return util.lines(
		M.command(
			"list-sessions -F "
				.. util.shell_quote(
					"#{session_name}\t#{pane_current_path}\t" .. "#{session_last_attached}\t#{session_attached}"
				)
		)
	)
end

function M.list_panes(format)
	return util.lines(M.command("list-panes -a -F " .. util.shell_quote(format)))
end

function M.list_windows_all(format)
	return util.lines(M.command("list-windows -a -F " .. util.shell_quote(format)))
end

function M.list_windows(session, format)
	return util.lines(M.command("list-windows -t " .. util.shell_quote(session) .. " -F " .. util.shell_quote(format)))
end

function M.list_window_panes(target, format)
	return util.lines(M.command("list-panes -t " .. util.shell_quote(target) .. " -F " .. util.shell_quote(format)))
end

function M.info(target, format)
	local output = M.run("display-message -p -t " .. util.shell_quote(target) .. " " .. util.shell_quote(format))
	return output and output:gsub("\r?\n$", "")
end

function M.capture_pane(pane, start_line)
	local start = tostring(start_line or -120)
	if not start:match("^%-?%d+$") then
		start = "-120"
	end
	return M.run("capture-pane -p -e -J -t " .. util.shell_quote(pane) .. " -S " .. util.shell_quote(start) .. " -E -1")
end

return M
