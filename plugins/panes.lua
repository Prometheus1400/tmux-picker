return {
	api_version = 1,
	id = "panes",
	setup = function(ctx)
		ctx.register_view(require("tmux_picker.views").definition("panes"))
	end,
}
