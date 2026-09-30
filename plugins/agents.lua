return {
	api_version = 1,
	id = "agents",
	setup = function(ctx)
		local config, util, tmux = ctx.config, ctx.util, ctx.tmux
		if not (util.run("PATH=" .. util.shell_quote(config.path_prefix) .. " command -v python3 2>/dev/null") or ""):match("%S") then
			return
		end
		local function records()
			local socket = util.trim(tmux.run("display-message -p '#{socket_path}'"))
			if socket == "" then return {} end
			local output = util.run("PATH=" .. util.shell_quote(config.path_prefix) .. " python3 "
				.. util.shell_quote(config.root .. "/bin/tmux-picker-agents") .. " list --socket " .. util.shell_quote(socket))
			local result = ctx.json.decode(output or "")
			local enabled = {}
			for _, record in ipairs(type(result) == "table" and result or {}) do
				if config.agents.providers[record.provider] ~= false then enabled[#enabled + 1] = record end
			end
			return enabled
		end
		local function find(target)
			for _, record in ipairs(records()) do
				if record.id == target then return record end
			end
		end
		local function list()
			for _, record in ipairs(records()) do
				local color = ({ waiting = config.colors.yellow, working = config.colors.green,
					idle = config.colors.blue })[record.status] or config.colors.muted
				ctx.emit({kind = "agent", target = record.id, source = record.provider,
					name = color .. util.pad_visible(record.status, 8) .. config.colors.reset .. " " .. record.provider .. "  "
						.. util.clean_field(record.location) .. "  " .. util.clean_field(record.cwd),
					extra = util.clean_field(record.reason)})
			end
		end
		ctx.register_view({id = "agents", order = 40, label = "agents", key = "ctrl-g", chord = "C-g",
			prompt = "agents > ", color = config.colors.green, list = list,
			keys = {{key = "ctrl-r", chord = "C-r", label = "refresh", action = "agents.refresh"}}})
		ctx.register_action("agents.refresh", function(_, view) return {reload = true, view = view} end)
		ctx.register_kind("agent", {
			accept = function(row)
				local record = find(row.target)
				if record then tmux.switch_pane(record.pane) else ctx.notify("agent is no longer running") end
			end,
			preview = function(row)
				local record = find(row.target)
				if not record then io.write("Agent is no longer running\n"); return end
				io.write(record.provider, " · ", util.clean_field(record.status), " · ", util.clean_field(record.reason), "\n",
					util.clean_field(record.location), " · PID ", record.pid, "\n",
					util.clean_field(record.cwd), "\n")
				io.write("Status association: ", util.clean_field(record.association), "\n")
				if record.session_id ~= "" then io.write("Session: ", util.clean_field(record.session_id), "\n") end
				if record.updated_at > 0 then io.write("Updated: ", os.date("%Y-%m-%d %H:%M:%S", record.updated_at), "\n") end
				io.write("\n", tmux.capture_pane(record.pane, -60) or "")
			end,
			kill = function() ctx.notify("agent rows cannot be killed; use the panes view") end,
		})
	end,
}
