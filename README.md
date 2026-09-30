# tmux-picker

An extensible fzf popup for navigating tmux sessions, windows, and panes.

## Requirements

- tmux 3.3+
- fzf 0.71+ (`--popup` support)
- Lua 5.1+ or LuaJIT
- zoxide (optional first-party plugin)

Run `tmux-picker doctor` to check required commands and plugin load errors.

## TPM installation

```tmux
set -g @plugin 'Prometheus1400/tmux-picker'
```

Keep TPM initialization at the end of your tmux configuration, reload it, then
press Prefix-I to install. TPM installs the plugin in its configured plugins
directory and handles updates with Prefix-U.

The default binding is Prefix-o. Override it before TPM initializes:

```tmux
set -g @tmux-picker-key 's'
```

Set the option to an empty string to define bindings yourself:

```tmux
set -g @tmux-picker-key ''
bind-key o run-shell '#{@tmux-picker-command}'
```

`@tmux-picker-command` contains the shell command for the installed launcher.
You can set it before TPM initializes to use a custom launcher. Automatically
generated paths refresh when the checkout moves; explicit overrides are preserved.
Options named `@tmux-picker-default-command`, `@tmux-picker-bound-key`, and
`@tmux-picker-binding` are internal state and should not be configured manually.

### Dependency PATH

TPM does not install tmux, fzf, or Lua. They must be available in tmux's environment.
For fzf installed with `~/.fzf/install`, add `~/.fzf/bin` to your shell's PATH
before starting tmux. For an existing server, refresh its environment:

```sh
tmux set-environment -g PATH "$PATH"
tmux set-environment PATH "$PATH"
```

Run the installed launcher's dependency check:

```sh
~/.tmux/plugins/tmux-picker/bin/tmux-picker doctor
```

Adjust that path if you configured a different TPM plugins directory. `doctor`
checks command availability and extension load errors; compare `fzf --version`
and `tmux -V` with the requirements above separately.

## Standalone installation

Clone the package anywhere and invoke `bin/tmux-picker`:

```tmux
bind-key o run-shell '~/.local/share/tmux-picker/bin/tmux-picker'
```

The launcher discovers all Lua modules relative to itself, so the package
does not need to be on `PATH`.

## Window previews

The windows view (Ctrl-W) previews the pane split layout, labelled with each
pane's index and current process. `*` and green labels mark the active pane.
The diagram scales to fit the preview; full process names, sizes, and paths
remain listed below it. Zoomed windows show their full saved layout. Very
small previews fall back to the pane details.

## Configuration

Optional settings live in
`${XDG_CONFIG_HOME:-$HOME/.config}/tmux-picker/init.lua`:

```lua
return {
  size = "70%,80%",
  preview_window = "up,55%",
  hidden_sessions = { scratch = true },
  bundled_plugins = { zoxide = true },
}
```

## Plugins

First-party plugins bundled in `plugins/` load before every `*.lua` file under
`${XDG_CONFIG_HOME:-$HOME/.config}/tmux-picker/plugins`. Files in each
directory load in filename order. Plugins are trusted code and run with the
same permissions as the picker.

The bundled `zoxide.lua` plugin adds a dedicated Ctrl-X view when the `zoxide`
executable is available. The tmux-only core works without it.

Bundled plugins are enabled by default. Opt out of an individual plugin in
`~/.config/tmux-picker/init.lua` (or the equivalent under `XDG_CONFIG_HOME`):

```lua
return {
  bundled_plugins = { zoxide = false },
}
```

Set `zoxide = true` to opt back in; its executable must still be available on
the picker's PATH. Names are the bundled Lua filenames without `.lua`. Omitted
names remain enabled. A disabled plugin's file is not evaluated.

Set `bundled_plugins = false` to disable all bundled plugins while continuing
to load your user plugins. These settings apply the next time the picker opens.
`TMUX_PICKER_DISABLE_PLUGINS=1` takes precedence and disables both bundled and
user plugins.

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
LUA_BIN=lua tests/run
TPM_SOURCE="$HOME/.tmux/plugins/tpm" python3 tests/tpm.py
stylua --check lua tests
```

The integration test uses an isolated tmux server and temporary HOME and clones
the repository through TPM. It does not modify your running tmux server.

## License

MIT; see [LICENSE](LICENSE).
