return {
	api_version = 1,
	id = "zoxide",
	setup = function(ctx)
		local config = ctx.config
		local sessions = require("tmux_picker.sessions")
		local util = ctx.util

		local executable = util.run("PATH=" .. util.shell_quote(config.path_prefix) .. " command -v zoxide 2>/dev/null")
		if not executable or executable == "" then
			return
		end

		local function list()
			local command = "PATH=" .. util.shell_quote(config.path_prefix) .. " zoxide query -l 2>/dev/null"
			for _, path in ipairs(util.lines(command)) do
				ctx.emit({
					kind = "session",
					target = path,
					name = config.colors.teal .. "󰉋" .. "\27[39m " .. path,
					source = "zoxide",
					extra = "",
				})
			end
		end

		ctx.register_view({
			id = "zoxide",
			order = 30,
			label = "zoxide",
			key = "ctrl-x",
			chord = "C-x",
			prompt = "󰉋  ",
			color = config.colors.teal,
			list = list,
			query = sessions.connect,
		})

		ctx.register_supplement("sessions", list)
	end,
}
