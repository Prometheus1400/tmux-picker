local config = require("tmux_picker.config")
local util = require("tmux_picker.util")

local M = {}

function M.ref(path)
	if not path or path == "" then
		return nil
	end
	local prefix = "git -C " .. util.shell_quote(path) .. " "
	local ref = util.run(prefix .. "branch --show-current 2>/dev/null")
	ref = ref and util.trim(ref)
	if ref and ref ~= "" then
		return ref
	end
	ref = util.run(prefix .. "describe --tags --exact-match 2>/dev/null")
	ref = ref and util.trim(ref)
	return ref ~= "" and ref or nil
end

function M.decorate(ref)
	if not ref or ref == "" then
		return ""
	end
	return " " .. config.colors.muted .. config.icons.git .. " " .. ref .. config.colors.reset
end

return M
