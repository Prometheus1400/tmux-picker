local loader = require("tmux_picker.loader")
local configured = loader.configure()

local subprocess_commands = {list=true, current=true, preview=true, ["switch-view"]=true, action=true, ["execute-action"]=true,
	["fzf-enter"]=true, ["fzf-escape"]=true, kill=true, doctor=true}
if configured ~= false and not subprocess_commands[arg[1] or ""] then
	require("tmux_picker.packages").sync()
end

local config = require("tmux_picker.config")
local picker = require("tmux_picker.picker")
local registry = require("tmux_picker.registry")
local tmux = require("tmux_picker.tmux")
local util = require("tmux_picker.util")
local views = require("tmux_picker.views")

views.register_kinds()
loader.plugins()

local self_command = os.getenv("TMUX_PICKER_CMD") or ((os.getenv("TMUX_PICKER_ROOT") or "") .. "/bin/tmux-picker")

local function first_view()
	local view = registry.first_view()
	if not view then
		util.die("no picker views enabled; enable a bundled or user plugin")
	end
	return view
end

local function current_view()
	local id = util.read_file(config.view_file)
	id = id and id:gsub("\n$", "")
	return registry.view(id) and id or first_view().id
end

local function selected(text)
	local row
	local query
	for line in tostring(text or ""):gmatch("[^\n]+") do
		local candidate = util.row(line)
		if candidate.target ~= "" and registry.kind(candidate.kind) then
			row = candidate
		elseif line ~= "" then
			query = line
		end
	end
	return row, query
end

local function accept_output(text)
	local row, query = selected(text)
	if row then
		local handler = registry.kind(row.kind)
		if handler and handler.accept then
			handler.accept(row)
		end
		return
	end
	if query then
		local view = registry.view(current_view())
		if view and view.query then
			view.query(query)
		end
	end
end

local command = arg[1]

if command == "list" then
	local view = registry.view(arg[2]) or first_view()
	view.list()
	os.exit(0)
elseif command == "current" then
	registry.view(current_view()).list()
	os.exit(0)
elseif command == "preview" then
	local handler = registry.kind(arg[2] or "")
	if handler and handler.preview then
		handler.preview({
			kind = arg[2] or "",
			target = arg[3] or "",
			source = arg[4] or "",
		})
	end
	os.exit(0)
elseif command == "switch-view" then
	io.write(picker.switch_action(arg[2], self_command), "\n")
	os.exit(0)
elseif command == "action" or command == "execute-action" then
	local action = registry.action(arg[2] or "")
	local active_view = current_view()
	local restore = command == "execute-action" and (picker.header_action(active_view) .. "+") or ""
	if not action then
		io.write(restore, "ignore\n")
		os.exit(0)
	end
	if type(action) == "function" then action = { run = action } end
	local row = {
		kind = arg[3] or "",
		target = arg[4] or "",
	}
	local view_id = command == "execute-action" and (arg[5] or active_view) or active_view
	if command == "action" and action.pending then
		local ok, pending = pcall(action.pending, row, view_id)
		if ok and type(pending) == "string" and pending ~= "" then
			local rendered, payload = pcall(picker.pending_action, arg[2], row, view_id, pending, self_command)
			if rendered then io.write(payload, "\n"); os.exit(0) end
			util.notify(payload)
		elseif not ok then
			util.notify(pending)
		end
	end
	local ok, result = pcall(action.run, row, view_id)
	if not ok then
		util.notify(result)
		io.write(restore, "ignore\n")
	else
		io.write(restore, picker.render_action(result, active_view, self_command), "\n")
	end
	os.exit(0)
elseif command == "fzf-enter" then
	local row = { kind = arg[2] or "", target = arg[3] or "" }
	local result = registry.run_hooks("enter", row, arg[4] or "")
	io.write(result and picker.render_action(result, current_view(), self_command) or "accept", "\n")
	os.exit(0)
elseif command == "fzf-escape" then
	local result = registry.run_hooks("escape")
	io.write(result and picker.render_action(result, current_view(), self_command) or "abort", "\n")
	os.exit(0)
elseif command == "kill" then
	local kind = arg[2] or ""
	local target = arg[3] or ""
	local handler = registry.kind(kind)
	if handler and handler.kill then
		handler.kill({ kind = kind, target = target })
	else
		tmux.kill(kind, target)
	end
	os.exit(0)
elseif command == "doctor" then
	local failed = false
	if not registry.first_view() then
		io.write("missing picker views: enable a bundled or user plugin\n")
		failed = true
	end
	for _, dependency in ipairs({ "tmux", "fzf" }) do
		local output = util.run(
			"PATH="
				.. util.shell_quote(config.path_prefix)
				.. " command -v "
				.. util.shell_quote(dependency)
				.. " 2>/dev/null"
		)
		if output and output ~= "" then
			io.write("ok      ", dependency, "\n")
		else
			io.write("missing ", dependency, "\n")
			failed = true
		end
	end
	for _, err in ipairs(registry.errors()) do
		io.write("plugin  ", err, "\n")
		failed = true
	end
	os.exit(failed and 1 or 0)
end

util.need("fzf")
local view = registry.view(command) or first_view()
local output = picker.open(view.id, self_command)
if output and output ~= "" then
	accept_output(output)
end
