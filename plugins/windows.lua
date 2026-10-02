return {
	api_version = 1,
	id = "windows",
	setup = function(ctx)
		ctx.register_view(require("tmux_picker.views").definition("windows"))
	end,
}
