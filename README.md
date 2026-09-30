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

### Colors

Picker labels and previews use the terminal's ANSI palette by default. They
follow terminal themes such as Rose Pine without fixed RGB colors. The native
popup border follows your tmux `popup-border-style`.

fzf starts with its 16-color scheme before applying `FZF_DEFAULT_OPTS`, so your
existing fzf theme takes precedence. If `FZF_DEFAULT_OPTS_FILE` is set, its
options are respected without adding a scheme. tmux must receive these
environment variables when it starts, or through `tmux set-environment`.

Override individual label/preview colors in `init.lua`; omitted colors retain
their defaults. Values are ANSI escape sequences, and `""` disables a color:

```lua
return {
  colors = {
    blue = "\27[34m", -- terminal blue
    muted = "\27[90m", -- terminal bright black
    teal = "\27[38;2;156;207;216m", -- explicit RGB, if desired
  },
  -- Optional fzf colors for this picker; overrides matching global fzf colors.
  fzf_colors = "border:#ebbcba,label:#ebbcba,preview-border:#31748f",
}
```

Color keys are `muted`, `green`, `peach` (terminal red), `blue`, `teal` (cyan),
`yellow`, `mauve` (magenta), and `reset`. `colors` controls picker text;
`fzf_colors` accepts fzf's `--color` syntax for the finder UI. Neither sets the
native tmux border; configure that with `set -g popup-border-style`.

## Plugins

### Agents view

The bundled `agents` plugin adds **Ctrl-E** to discover coding agents running
inside panes on the current tmux server. Codex is the first supported provider.
It takes one process snapshot and walks descendants of each pane's shell;
ordinary `codex` launches work without a wrapper or changes to daemon behavior.
The optional view requires Python 3 (standard library only).

Rows show status, provider, session/window/pane location, and directory. Enter
focuses the exact pane, **Ctrl-R** refreshes, and the preview shows a compact
status header and recent conversation messages labelled **You** and **codex**.
Waiting agents sort before working and idle agents. Ctrl-D
does not kill agents; use the panes view for that. Lists refresh on entry and
Ctrl-R; they do not poll continuously.

Without hooks, running agents appear with `unknown` status. To add Codex status:

```sh
~/.tmux/plugins/tmux-picker/bin/tmux-picker-agents install-codex-hooks
```

Then open **`/hooks` in Codex** to review and trust the handlers. The command
merges handlers into `${CODEX_HOME:-$HOME/.codex}/hooks.json`, preserves other
hooks, saves the original to `hooks.json.tmux-picker-backup`, and is safe to
repeat after moving the plugin. To remove only the picker's handlers:

```sh
~/.tmux/plugins/tmux-picker/bin/tmux-picker-agents uninstall-codex-hooks
```

Prompt submission and tool activity mark `working`, approval requests mark
`waiting`, turn completion/interruption mark `idle`, and session end marks
`stopped`. These are last observed hook signals, not proof that every approval
or user question is still pending. Updates apply on the next refresh.

Hooks prefer process ancestry to associate a session with its pane. Shared
Codex daemon hooks may lack that ancestry; the adapter then infers association
only when exactly one Codex process on that server matches the hook's working
directory. The preview labels this inference. Multiple Codex instances in the
same directory remain `unknown` when no exact association is available, rather
than guessing between them. A hook without a tmux server remains unassociated.
Pane existence and process start time are rechecked to reject stale records.

State lives under `${XDG_STATE_HOME:-$HOME/.local/state}/tmux-picker/agents`.
Records contain metadata only, including the transcript path provided by Codex;
prompts, responses, and tool arguments are not copied into picker state. The
conversation preview reads that existing transcript on demand, using at most
256 KiB of its tail and displaying the last eight user/assistant messages.
Long messages are shortened; system/developer instructions, reasoning, and
tool calls are omitted. Transcript formats are version-dependent, so an
unavailable or unsupported transcript produces a notice instead of pane output.
The hook prints no agent instructions and never makes approval decisions.

Disable this first-party plugin, or a provider, in `init.lua`:

```lua
return {
  bundled_plugins = { agents = false },
  -- Alternatively keep the view and disable only Codex:
  -- agents = { providers = { codex = false } },
}
```

Disabling the view does not uninstall separately configured Codex hooks; use
the uninstall command to stop recording status.

Provider adapters live in `bin/agent_providers/`. Each exposes `matches(process)`
and an `events` map translating native hook names into `(status, reason)` pairs.
`conversation(record)` returns recent `{role, text}` messages and an optional
availability notice for that provider's native conversation storage.
Register a new adapter in `PROVIDERS`, and supply its native hook configuration;
the shared discovery, storage, sorting, and Agents view need no provider-specific
changes. `tmux-picker-agents hook <provider>` receives the adapter's event JSON
on stdin. The initial hook setup command is Codex-specific.

### Plugin API

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
