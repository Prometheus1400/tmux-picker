# tmux-picker

An extensible fzf popup for navigating tmux sessions, zoxide directories,
windows, and panes.

## Requirements

- tmux
- fzf with popup support
- Lua 5.1+ or LuaJIT
- zoxide (optional; its view is empty when unavailable)

Run `tmux-picker doctor` to check required commands and plugin load errors.

## TPM installation

```tmux
set -g @plugin 'your-name/tmux-picker'
```

The default binding is Prefix-o. Override it before TPM initializes:

```tmux
set -g @tmux-picker-key 's'
```

Set the option to an empty string to define bindings yourself:

```tmux
set -g @tmux-picker-key ''
bind-key o run-shell '#{@tmux-picker-command}'
```

## Standalone installation

Clone the package anywhere and invoke `bin/tmux-picker`:

```tmux
bind-key o run-shell '~/.local/share/tmux-picker/bin/tmux-picker'
```

The launcher discovers all Lua modules relative to itself, so the package
does not need to be on `PATH`.

## Configuration

Optional settings live in
`${XDG_CONFIG_HOME:-$HOME/.config}/tmux-picker/init.lua`:

```lua
return {
  size = "70%,80%",
  preview_window = "up,55%",
  hidden_sessions = { scratch = true },
}
```

## Plugins

Every `*.lua` file under
`${XDG_CONFIG_HOME:-$HOME/.config}/tmux-picker/plugins` is loaded in filename
order. Plugins are trusted code and run with the same permissions as the
picker.

A plugin returns a descriptor:

```lua
return {
  api_version = 1,
  id = "example",
  setup = function(ctx)
    ctx.register_view({
      id = "example",
      order = 60,
      label = "example",
      key = "ctrl-g",
      chord = "C-g",
      prompt = "> ",
      list = function()
        ctx.emit({
          kind = "example",
          target = "value",
          name = "Example value",
        })
      end,
      query = function(query)
        -- Handle Enter when no row is selected.
      end,
      keys = {
        {
          key = "ctrl-r",
          chord = "C-r",
          label = "refresh",
          action = "example.refresh",
        },
      },
    })

    ctx.register_kind("example", {
      accept = function(row) end,
      preview = function(row) end,
      kill = function(row) end,
    })

    ctx.register_action("example.refresh", function(row, view_id)
      return { reload = true, view = view_id, notice = "refreshed" }
    end)
  end,
}
```

Other extension points are:

- `register_decorator(scope, fn)` for `session`, `window`, `pane`, or
  `command` display values.
- `register_supplement(view_id, fn)` to append rows to a core view.
- `register_hook(event, fn)` for `open`, `view_change`, `enter`, and `escape`.

The context also exposes `config`, `util`, `tmux`, `git`, `json`, `notify`,
and `decorate`.

Plugin IDs, view IDs, row-kind IDs, and action IDs must be unique. Prefix
plugin-owned actions with the plugin ID. A plugin that fails during setup is
rolled back and reported by `doctor`; other views continue to load.

Set `TMUX_PICKER_PLUGIN_DIR` to test another plugin directory, or
`TMUX_PICKER_DISABLE_PLUGINS=1` to run only the core.

## Development

Run:

```sh
tests/run
stylua --check lua tests
```
