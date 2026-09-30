local config = require("tmux_picker.config")
local git = require("tmux_picker.git")
local registry = require("tmux_picker.registry")
local tmux = require("tmux_picker.tmux")
local util = require("tmux_picker.util")

local M = {}

local function rows()
	local output = {}
	for _, line in ipairs(tmux.list_session_paths()) do
		local name, path, attached_at, clients = util.split_tab(line, 4)
		if name and name ~= "" and not config.hidden_sessions[name] then
			output[#output + 1] = {
				name = name,
				path = path or "",
				attached_at = tonumber(attached_at) or 0,
				clients = tonumber(clients) or 0,
			}
		end
	end
	table.sort(output, function(left, right)
		if left.attached_at ~= right.attached_at then
			return left.attached_at > right.attached_at
		end
		return left.name < right.name
	end)
	return output
end

function M.allowed()
	local output = {}
	for _, row in ipairs(rows()) do
		output[row.name] = true
	end
	return output
end

function M.connect(target)
	target = util.trim(target)
	if target == "" then
		return
	end
	if target:sub(1, 1) == "/" then
		if not util.is_dir(target) then
			return
		end
		local name = util.basename(target)
		if name then
			tmux.ensure_session(name:lower(), target)
			tmux.switch_session(name:lower())
		end
		return
	end
	tmux.ensure_session(target)
	tmux.switch_session(target)
end

function M.list_tmux(options)
	options = options or {}
	for _, row in ipairs(rows()) do
		if not options.hide_attached or row.clients == 0 then
			local name = config.colors.blue .. config.icons.session .. "\27[39m " .. row.name
			name = registry.decorate("session", name, row)
			util.emit({
				kind = "session",
				target = row.name,
				name = name,
				source = "tmux",
				extra = git.decorate(git.ref(row.path)),
			})
		end
	end
end

return M
