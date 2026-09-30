return {
	api_version = 1,
	id = "example",
	setup = function(ctx)
		ctx.register_view({
			id = "example",
			label = "example",
			key = "ctrl-g",
			prompt = "> ",
			list = function() end,
			query = function() end,
		})
		ctx.register_kind("example", {
			accept = function() end,
			preview = function() end,
		})
		ctx.register_action("example.reload", function()
			return { reload = true, view = "example" }
		end)
		ctx.register_decorator("session", function(value)
			return value .. " decorated"
		end)
		ctx.register_supplement("sessions", function(context)
			context.seen = true
		end)
	end,
}
