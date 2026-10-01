# tmux-picker

Jump between tmux sessions, windows, panes, directories, and coding agents from
one extensible fzf popup.

**Prefix-o** opens the picker. Type to filter, switch views, and press **Enter**
to jump to your selection.

| Key | View | What you'll find |
| --- | --- | --- |
| **Ctrl-T** | Sessions | Sessions with window and pane details in the preview |
| **Ctrl-W** | Windows | Pane layout and running processes |
| **Ctrl-O** | Panes | Individual panes with recent pane content in the preview |
| **Ctrl-X** | zoxide | Directories from zoxide; Enter creates or switches to a tmux session |
| **Ctrl-E** | Agents | Running Codex sessions and recent conversation |

The zoxide and Agents views are bundled plugins. They appear when enabled and
their dependencies are available; conversation previews also need Codex hooks.

[Install](#install) · [Configure](#configure) · [Codex setup](#codex-setup) ·
[Third-party plugins](#third-party-plugins) · [Write your own plugin](#write-your-own-plugin) ·
[Plugin API](#plugin-api)

## Install

### With TPM

Add this **before TPM initialization** in your tmux configuration:

```tmux
set -g @plugin 'Prometheus1400/tmux-picker'
```

Reload the configuration → **Prefix-I** installs → **Prefix-o** opens.
Use **Prefix-U** for TPM updates. Keep TPM initialization at the end of the
configuration; it uses your configured TPM plugins directory.

| Dependency | Version | Required for |
| --- | --- | --- |
| Bash | System Bash | Launcher and TPM entry point |
| tmux | 3.3+ | Core picker |
| fzf | 0.71+ | Core picker (`--popup` support) |
| Lua / LuaJIT | Lua 5.1+ or LuaJIT | Core picker runtime |
| zoxide | — | Optional directory view |
| Python 3 | 3.9+ for reconciliation | Optional Agents view and third-party plugin reconciliation |
| Git | — | Third-party plugin reconciliation; optional branch/tag labels |

TPM installs the picker. Its dependencies must already be available in tmux's
`PATH`. Check the installation:

```sh
~/.tmux/plugins/tmux-picker/bin/tmux-picker doctor
fzf --version
tmux -V
```

`doctor` checks command availability and plugin errors; check versions separately
against the table. Adjust the launcher path for a custom TPM plugins directory.
You can also run `tmux-picker doctor` if the launcher is on your `PATH`.

<details>
<summary>tmux cannot find fzf or Lua</summary>

For fzf installed with `~/.fzf/install`, put `~/.fzf/bin` on your shell's `PATH`
before starting tmux. Refresh both environments on an existing server:

```sh
tmux set-environment -g PATH "$PATH"
tmux set-environment PATH "$PATH"
```

</details>

<details>
<summary>Change the binding or launcher</summary>

Set options before TPM initializes:

```tmux
# Open with Prefix-s.
set -g @tmux-picker-key 's'
```

Or define your own binding:

```tmux
set -g @tmux-picker-key ''
bind-key o run-shell '#{@tmux-picker-command}'
```

`@tmux-picker-command` contains the installed launcher's shell command. Set it
explicitly to use a custom launcher. Generated paths refresh when the checkout
moves; explicit overrides are preserved.

Leave the internal options `@tmux-picker-default-command`,
`@tmux-picker-bound-key`, and `@tmux-picker-binding` to the plugin.

</details>

### Without TPM

```sh
git clone https://github.com/Prometheus1400/tmux-picker.git \
  ~/.local/share/tmux-picker
```

```tmux
bind-key o run-shell '~/.local/share/tmux-picker/bin/tmux-picker'
```

The checkout can live anywhere. `bin/tmux-picker` finds its Lua modules relative
to itself; adding its `bin` directory to `PATH` is optional. Hook setup commands
below use the TPM path; substitute your standalone checkout's path if needed.

## Preview the destination

### Windows · Ctrl-W

A window with three panes looks like this:

```text
┌───────────────────────┬───────────────────────┐
│                       │                       │
│                       │        pane 1         │
│                       │         codex         │
│                       │                       │
│       pane 0 *        ├───────────────────────┤
│         nvim          │                       │
│                       │        pane 2         │
│                       │          zsh          │
│                       │                       │
└───────────────────────┴───────────────────────┘
```

`*` and green labels identify the active pane. The diagram scales to fit, with
full process names, pane sizes, and paths listed below. Zoomed windows still
show the complete saved layout; very small previews show pane details instead.

### Agents · Ctrl-E

Example rows:

```text
waiting  codex  app:1.0      /work/app       approval requested
working  codex  dotfiles:2.1 /work/dotfiles  using tool
idle     codex  docs:0.0     /work/docs      turn completed
```

Example preview:

```text
codex conversation · working
app:1.0 · /work/app
using tool · 14:32:08

You
Add keyboard navigation to the picker.

codex
The bindings are in place. I'm checking the selection behavior.
```

| Action | Behavior |
| --- | --- |
| **Enter** | Verify the agent is still running, then focus its exact pane |
| **Ctrl-R** | Refresh agents and status |
| Switch to Agents | Refresh the list; waiting sorts before working and idle |
| **Ctrl-D** | Leaves agents running; use the panes view to kill a pane |

The view discovers Codex through descendants of each pane's shell on the current
tmux server. Launch `codex` normally; no wrapper or daemon changes are needed.
Python 3 is the only extra runtime, using its standard library and the system
`ps` command. Lists refresh on entry and Ctrl-R, with no continuous polling.

## Codex setup

Running agents appear immediately. Hooks add status and link conversation previews:

```sh
~/.tmux/plugins/tmux-picker/bin/tmux-picker-agents install-codex-hooks
```

In Codex, open **`/hooks`** and review/trust the tmux-picker handlers. For an
existing session, exit and use `codex resume` to reopen the same conversation
with the new hook configuration. Refresh the Agents view with **Ctrl-R**.

| Observed event | Status |
| --- | --- |
| Session start (except compaction) | `idle` |
| Prompt submission or tool activity | `working` |
| Approval request | `waiting` |
| Turn completion or interruption | `idle` |
| Session end | `stopped` |
| No associated hook status | `unknown` |

Status is the last observed signal; it does not prove that an approval or user
question is still pending. Rows update on list refresh; the preview picks up
new hook status when you navigate to an agent.

<details>
<summary>Hook installation, removal, and pane association</summary>

The installer merges handlers into `${CODEX_HOME:-$HOME/.codex}/hooks.json`,
preserves other hooks, and saves an existing file to `hooks.json.tmux-picker-backup`
if that backup does not already exist.
Repeat it safely after moving the plugin. Remove only the picker's handlers with:

```sh
~/.tmux/plugins/tmux-picker/bin/tmux-picker-agents uninstall-codex-hooks
```

| Association | Result |
| --- | --- |
| Hook process ancestry identifies the CLI | Link to its pane |
| Shared daemon; one Codex process matches the hook's directory | Link with an **inferred** label in the preview |
| Multiple same-directory agents, with no exact link | Keep status `unknown` |
| Hook has no tmux server | Keep the event unassociated |

Process start times and pane ownership reject stale records. Disabling the
Agents view leaves independently installed hooks in place; uninstall the hooks
to stop recording status. Hooks never inject instructions or make approval decisions.

</details>

<details>
<summary>Conversation storage and preview performance</summary>

| Data | Handling |
| --- | --- |
| Agent state | `${XDG_STATE_HOME:-$HOME/.local/state}/tmux-picker/agents` |
| Saved fields | Metadata, including Codex's transcript path |
| Conversation text | Read from the existing transcript; never copied or cached in picker state |
| Read limit | At most 256 KiB from the transcript tail |
| Display limit | Up to eight recent user/assistant messages from that tail; each is shortened after 1,600 characters |
| Omitted content | System/developer instructions, reasoning, and tool calls |
| Missing or unsupported transcript | An availability notice in the preview |

Transcript formats vary by Codex version. The list caches agent metadata;
navigating validates only the selected process and pane, picks up new hook
status, and reads the bounded transcript tail. Enter performs fresh discovery
before switching panes.

</details>

## Configure

Settings are optional. Create or edit
`${XDG_CONFIG_HOME:-$HOME/.config}/tmux-picker/init.lua`:

```lua
return {
  size = "70%,80%",
  preview_window = "up,55%",
  hidden_sessions = { scratch = true },
  bundled_plugins = {
    zoxide = true,
    agents = true,
  },
  agents = { providers = { codex = true } },
}
```

The snippets below are alternatives or additions to this file. Combine their
fields in one returned table; unspecified settings keep their defaults.

### Choose bundled plugins

```lua
return {
  bundled_plugins = { zoxide = false }, -- keep Agents; disable zoxide
}
```

| Setting | Effect on the next picker launch |
| --- | --- |
| `bundled_plugins = { agents = false }` | Disable Agents |
| `agents = { providers = { codex = false } }` | Keep the view; disable its Codex provider |
| `bundled_plugins = false` | Disable all bundled plugins; keep user plugins |
| `TMUX_PICKER_DISABLE_PLUGINS=1` | Disable all plugins and Git reconciliation |

Bundled plugins default to enabled, including omitted names. Set a name to `true`
to opt back in; zoxide still needs its executable on the picker's `PATH`.
Names are Lua filenames in `plugins/` without `.lua`. Disabled bundled files
are not evaluated. The tmux-only core works without optional plugins.

### Match your colors

| Surface | Default / override |
| --- | --- |
| Picker labels and previews | Terminal ANSI palette; override with `colors` |
| fzf UI | 16-color fallback, then `FZF_DEFAULT_OPTS`; override with `fzf_colors` |
| Native popup border | tmux `popup-border-style` |

Defaults follow terminal palettes such as Rose Pine. With `FZF_DEFAULT_OPTS_FILE`
set, its options are respected without adding a color scheme. Give tmux these
environment variables at startup or with `tmux set-environment`.

```lua
return {
  colors = {
    blue = "\27[34m",                -- terminal blue
    muted = "\27[90m",               -- terminal bright black
    teal = "\27[38;2;156;207;216m",    -- explicit RGB
    yellow = "",                    -- disable this text color
  },
  fzf_colors = "border:#ebbcba,label:#ebbcba,preview-border:#31748f",
}
```

Omitted text colors keep their defaults. Values are ANSI escape sequences.
`fzf_colors` uses fzf's `--color` syntax and overrides matching global fzf colors.
Neither option changes the native border:

```tmux
set -g popup-border-style 'fg=blue'
```

Available color keys: `muted`, `green`, `peach` (red), `blue`, `teal` (cyan),
`yellow`, `mauve` (magenta), and `reset`.

## Third-party plugins

Declare picker plugin repositories in `init.lua`; opening the picker reconciles
the configuration automatically:

```lua
return {
  plugins = {
    "owner/example-picker-plugin", -- GitHub shorthand; loads plugin.lua
    {
      repo = "https://github.com/owner/another-plugin.git",
      name = "another",
      entry = "plugins/main.lua",
      version = "v1.2.0",
      enabled = true,
    },
  },
  plugins_update_interval = 86400,
}
```

Replace the example repos with extensions implementing the [picker API](#plugin-api).
TPM continues to manage tmux plugins. Git and Python 3 handle picker reconciliation;
there are no install/update commands.

| Plugin field | Default | Accepted value |
| --- | --- | --- |
| `repo` | Required | GitHub `owner/repo`, HTTPS/SSH Git URL, absolute local repo path |
| `name` | Repository basename without `.git` | Unique checkout name: letters/digits first, then letters/digits, `_`, `.`, or `-` |
| `entry` | `plugin.lua` | Relative `.lua` path inside the repo; no `..` components |
| `version` | Track default branch | Tag, commit SHA, or named branch |
| `enabled` | `true` | `false` to stop loading and synchronization |

`plugins_update_interval` is a top-level setting, in seconds (default `86400`).
Set it to `0` to check branches on every open.

### Edit config → reopen picker

| Config change / condition | Reconciliation |
| --- | --- |
| Add an enabled repo | Clone it and load its entry |
| Change repo, entry, or version | Attempt the change on the next open |
| Pin a tag or SHA | Keep that version fixed |
| Select a branch | Track it; check for updates once a day by default |
| Set `enabled = false` | Keep an installed checkout, skip evaluation and fetching; don't clone a missing one |
| Remove a declaration | Remove its managed checkout |
| Local edits, untracked files, or ignored files | Preserve them; block update/removal |
| Update fails or network is offline | Retain the prior working checkout |
| Changed repo, entry, or version cannot be applied | Preserve the checkout; skip loading a copy that no longer matches the declaration |

Managed checkouts live in
`${XDG_DATA_HOME:-$HOME/.local/share}/tmux-picker/plugins`. Reconciliation runs
only when opening the picker, never in list, preview, action, or `doctor`
subprocesses. `doctor` reports saved synchronization errors and current plugin
load errors; it does not fetch or update repositories. Core views can still run
local Git queries for branch/tag labels.

<details>
<summary>Manual plugins and load order</summary>

```text
1. Bundled plugins/                         filename order
2. ~/.config/tmux-picker/plugins/*.lua       filename order
3. Repositories declared in init.lua         declaration order
```

The manual directory follows `XDG_CONFIG_HOME`; `TMUX_PICKER_PLUGIN_DIR` overrides
it for testing or a different location. Existing manual files continue to work
and are never managed or removed. Files in nested directories are not scanned.

All plugins are trusted Lua code with the picker's permissions.
`TMUX_PICKER_DISABLE_PLUGINS=1` skips both loading and reconciliation.

</details>

## Write your own plugin

Create a Lua file directly in
`${XDG_CONFIG_HOME:-$HOME/.config}/tmux-picker/plugins/`:

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/tmux-picker/plugins"
${EDITOR:-vi} "${XDG_CONFIG_HOME:-$HOME/.config}/tmux-picker/plugins/example.lua"
```

Paste the descriptor below into `example.lua`, fill in its handlers, and reopen
the picker. Files directly in this directory load automatically in filename
order; nested directories are not scanned. No repository, `plugins` declaration,
Git, Python, or package manager is needed to load a local Lua plugin. Your plugin
may require additional dependencies for its own features.

If you later want to share it as a managed plugin, put the same descriptor in a
repository as `plugin.lua` (or configure another `entry`) and use a
[repository declaration](#third-party-plugins).

## Plugin API

<details>
<summary>Plugin descriptor: view, rows, action handlers, and refresh</summary>

Save this as `plugin.lua` in a plugin repository, or as `example.lua` in the
manual plugin directory. This scaffold emits one example row. Fill in the empty
selection, preview, and kill handlers with your plugin's behavior:

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

</details>

| Extension point | Scope |
| --- | --- |
| `register_view` | Views, shortcuts, prompts, query handling, and action keys |
| `register_kind` | Row selection, preview, and kill behavior |
| `register_action` | Custom actions, including reload responses |
| `register_decorator(scope, fn)` | `session`, `window`, `pane`, or `command` display values |
| `register_supplement(view_id, fn)` | Append rows to a core view |
| `register_hook(event, fn)` | `open`, `view_change`, `enter`, or `escape` |

`ctx` also exposes `config`, `util`, `tmux`, `git`, `json`, `notify`, and `decorate`.
Plugin, view, row-kind, and action IDs must be unique; prefix plugin-owned actions
with the plugin ID. Failed setup rolls back that plugin, reports through `doctor`,
and lets other views continue to load.

<details>
<summary>Add another coding-agent provider</summary>

Adapters live in `bin/agent_providers/`:

| Adapter member | Contract |
| --- | --- |
| `matches(process)` | Detect the provider's running process |
| `events` | Map native hook names to `(status, reason)` |
| `conversation(record)` | Return recent `{role, text}` messages and an optional availability notice |

Register the adapter in `PROVIDERS` and supply its native hook configuration.
Shared discovery, state, sorting, and the Agents view need no provider-specific
changes. `tmux-picker-agents hook <provider>` reads event JSON from stdin;
the bundled hook setup command currently supports Codex.

</details>

## Development

```sh
tests/run
LUA_BIN=lua tests/run
TPM_SOURCE="$HOME/.tmux/plugins/tpm" python3 tests/tpm.py
stylua --check lua tests
```

The TPM integration tests clone through TPM in an isolated tmux server with a
temporary `HOME`; they leave your running server alone. Use
`TMUX_PICKER_PLUGIN_DIR` to point at test extensions, or
`TMUX_PICKER_DISABLE_PLUGINS=1` to run only the core.

## License

[MIT](LICENSE).
