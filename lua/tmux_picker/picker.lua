local config = require("tmux_picker.config")
local registry = require("tmux_picker.registry")
local tmux = require("tmux_picker.tmux")
local util = require("tmux_picker.util")

local M = {}

local function quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function M.legend(active_id, notice)
	local items = {}
	for _, view in ipairs(registry.views()) do
		if view.key then
			local text = (view.chord or view.key) .. " " .. (view.label or view.id)
			if view.id == active_id then
				text = "\27[1m" .. (view.color or config.colors.blue) .. text .. config.colors.reset
			else
				text = config.colors.muted .. text .. config.colors.reset
			end
			items[#items + 1] = text
		end
	end
	items[#items + 1] = config.colors.muted .. "C-d kill" .. config.colors.reset
	local view = registry.view(active_id)
	for _, binding in ipairs(view and view.keys or {}) do
		items[#items + 1] = config.colors.muted
			.. (binding.chord or binding.key)
			.. " "
			.. (binding.label or binding.action)
			.. config.colors.reset
	end
	local legend = "  " .. table.concat(items, "  ")
	if notice and notice ~= "" then
		legend = "  " .. notice .. "  ·" .. legend
	end
	return legend
end

function M.switch_action(view_id, self_command)
	local view = registry.view(view_id)
	if not view then
		return "ignore"
	end
	registry.run_hooks("view_change", view_id)
	util.write_file(config.view_file, view_id .. "\n")
	util.write_file(config.prompt_file, view.prompt .. "\n")
	return "enable-search+change-prompt("
		.. view.prompt
		.. ")+change-preview-window("
		.. view.preview_window
		.. ")+reload("
		.. quote(self_command)
		.. " list "
		.. quote(view_id)
		.. ")+change-header("
		.. M.legend(view_id)
		.. ")"
end

function M.render_action(result, current_view, self_command)
	if type(result) == "string" then
		return result
	end
	if type(result) ~= "table" then
		return "ignore"
	end
	if result.raw then
		return result.raw
	end
	if result.reload then
		local view_id = result.view or current_view
		return "reload("
			.. quote(self_command)
			.. " list "
			.. quote(view_id)
			.. ")+change-header("
			.. M.legend(view_id, result.notice)
			.. ")"
	end
	return "ignore"
end

function M.open(view_id, self_command)
	local view = registry.view(view_id) or registry.first_view()
	if not view then
		util.die("no picker views registered")
	end
	view_id = view.id
	util.write_file(config.view_file, view_id .. "\n")
	util.write_file(config.prompt_file, view.prompt .. "\n")
	tmux.save_socket()
	registry.run_hooks("open", view_id)

	local self_q = quote(self_command)
	local binds = {
		"--bind " .. quote("tab:down,btab:up"),
		"--bind " .. quote("enter:transform:" .. self_q .. " fzf-enter {1} {2} {q}"),
		"--bind " .. quote("start:execute-silent(stty -ixon < /dev/tty 2>/dev/null || true)"),
		"--bind " .. quote("esc:transform:" .. self_q .. " fzf-escape"),
		"--bind " .. quote("ctrl-d:execute-silent(" .. self_q .. " kill {1} {2})+reload(" .. self_q .. " current)"),
	}

	for _, candidate in ipairs(registry.views()) do
		if candidate.key then
			binds[#binds + 1] = "--bind "
				.. quote(candidate.key .. ":transform:" .. self_q .. " switch-view " .. quote(candidate.id))
		end
		for _, binding in ipairs(candidate.keys or {}) do
			binds[#binds + 1] = "--bind "
				.. quote(binding.key .. ":transform:" .. self_q .. " action " .. quote(binding.action) .. " {1} {2}")
		end
	end

	local fzf = string.format(
		[[PATH=%s TMUX_PANE= fzf --popup %s --border=none \
      --ansi --print-query \
      --delimiter='\t' --with-nth=3,5 --tabstop=1 --tiebreak=begin,index \
      --color='border:#89b4fa,label:#89b4fa,preview-border:#89b4fa' \
      --prompt %s --header %s \
      --preview %s --preview-window %s \
      %s]],
		quote(config.path_prefix),
		quote(view.size .. ",border-native"),
		quote(view.prompt),
		quote(M.legend(view_id)),
		quote(self_q .. " preview {1} {2} {4}"),
		quote(view.preview_window),
		table.concat(binds, " \\\n      ")
	)
	local list_command = string.format("PATH=%s %s list %s", quote(config.path_prefix), self_q, quote(view_id))
	local handle = io.popen(list_command .. " | " .. fzf)
	if not handle then
		return nil
	end
	local output = handle:read("*a")
	local ok, reason, code = handle:close()
	if not ok and code ~= 1 and code ~= 130 then
		error("fzf exited " .. tostring(code or reason or "unknown status"))
	end
	return output
end

return M
