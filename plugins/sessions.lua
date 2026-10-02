return {
	api_version = 1,
	id = "sessions",
	setup = function(ctx)
		ctx.register_view(require("tmux_picker.views").definition("sessions"))
	end,
}
