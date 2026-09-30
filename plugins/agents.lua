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
		local function plain(text)
			-- Transcript text must not inject terminal escapes into the preview.
			return tostring(text or ""):gsub("\27%[[0-?]*[ -/]*[@-~]", "")
				:gsub("[%z\1-\8\11-\31\127]", "")
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
		ctx.register_view({id = "agents", order = 40, label = "agents", key = "ctrl-e", chord = "C-e",
			prompt = "agents > ", color = config.colors.green, list = list,
			keys = {{key = "ctrl-r", chord = "C-r", label = "refresh", action = "agents.refresh"}}})
		ctx.register_action("agents.refresh", function(_, view) return {reload = true, view = view} end)
		ctx.register_kind("agent", {
			accept = function(row)
				local record = find(row.target)
				if record then tmux.switch_pane(record.pane) else ctx.notify("agent is no longer running") end
			end,
			preview = function(row)
				local socket = (os.getenv("TMUX") or ""):match("^([^,]+)")
					or util.trim(tmux.run("display-message -p '#{socket_path}'"))
				local output = util.run("PATH=" .. util.shell_quote(config.path_prefix) .. " python3 "
					.. util.shell_quote(config.root .. "/bin/tmux-picker-agents") .. " conversation --socket "
					.. util.shell_quote(socket) .. " --target " .. util.shell_quote(row.target))
				local conversation = ctx.json.decode(output or "") or {}
				local record = conversation.record
				if not record or config.agents.providers[record.provider] == false then
					io.write(plain(conversation.notice or "Agent is no longer running"), "\n"); return
				end
				local chunks = {}
				local function write(...)
					for index = 1, select("#", ...) do chunks[#chunks + 1] = tostring(select(index, ...)) end
				end
				write(config.colors.green, "\27[1m", record.provider, " conversation", config.colors.reset,
					"  · ", plain(record.status), "\n", config.colors.muted, plain(record.location),
					"  · ", plain(record.cwd), config.colors.reset, "\n", plain(record.reason))
				if record.updated_at > 0 then write(" · ", os.date("%H:%M:%S", record.updated_at)) end
				write("\n")
				if record.association == "unique directory (inferred)" then
					write(config.colors.muted, "Session association inferred from directory", config.colors.reset, "\n")
				end
				for _, message in ipairs(conversation.messages or {}) do
					local user = message.role == "user"
					write("\n", user and config.colors.blue or config.colors.green, "\27[1m",
						user and "You" or record.provider, config.colors.reset, "\n", plain(message.text), "\n")
				end
				if #(conversation.messages or {}) == 0 then
					write("\n", config.colors.muted, plain(conversation.notice or "Conversation unavailable"), config.colors.reset, "\n")
				end
				io.write(table.concat(chunks))
			end,
			kill = function() ctx.notify("agent rows cannot be killed; use the panes view") end,
		})
	end,
}
