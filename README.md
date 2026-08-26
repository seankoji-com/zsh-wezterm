# zsh-wezterm

Shell integration for [WezTerm](https://wezterm.org). WezTerm ships integration
for bash and fish; this is the zsh equivalent.

| Feature | What you get |
|---|---|
| OSC 7 | New splits and tabs open in the directory the pane you split from was in |
| OSC 133 | `ScrollToPrompt` works, and each command's output is a selectable semantic zone |
| `repo_name` user var | Tab bar can title and colour tabs by repository |
| `busy` user var | Tab bar can show which panes are mid-command |

## Install

oh-my-zsh:

```sh
git clone https://github.com/seankoji-com/zsh-wezterm \
  ~/.oh-my-zsh_custom/plugins/zsh-wezterm
```

```zsh
plugins=(... zsh-wezterm)
```

Anything else: source `zsh-wezterm.plugin.zsh` from `.zshrc`.

Load it *after* any plugin that registers its own `precmd` hooks, oh-my-zsh
included. See "Hook ordering" below for why.

## wezterm.lua

The user vars are inert until you read them. Minimal example:

```lua
wezterm.on('format-tab-title', function(tab)
  local repo = tab.active_pane.user_vars.repo_name
  local busy = tab.active_pane.user_vars.busy == '1'
  return { { Text = (busy and '● ' or '') .. (repo ~= '' and repo or tab.active_pane.title) } }
end)
```

Semantic zones need no Lua at all. Bind `ScrollToPrompt` and it works:

```lua
{ key = 'UpArrow', mods = 'CTRL|SHIFT', action = wezterm.action.ScrollToPrompt(-1) },
```

## Configuration

All default on. Set to `0` before the plugin loads.

| Variable | Controls |
|---|---|
| `ZSH_WEZTERM_OSC7` | Current-directory reporting |
| `ZSH_WEZTERM_OSC133` | Semantic prompt zones |
| `ZSH_WEZTERM_REPO_NAME` | The `repo_name` user var |
| `ZSH_WEZTERM_BUSY` | The `busy` user var |

## Public functions

`wezterm_set_user_var <name> <value>` publishes your own state to the tab bar.
Handles the base64 encoding and the terminal guard. Returns 0 when it declines
to emit, so it is safe in a `&&` chain.

```zsh
wezterm_set_user_var session_name "$(wezterm_repo_name)"
```

`wezterm_repo_name` returns the repository name for `$PWD`, empty outside a
repo. Prefers the origin remote's name, which stays correct inside a worktree
where the directory is named after the branch rather than the project.

`wezterm_urlencode <string>` percent-encodes for a `file://` URI.

`wezterm_is_wezterm` is true under WezTerm.

`zsh_wezterm_register` installs the hooks. Called automatically in an
interactive shell.

## Notes on the fiddly bits

**Terminal guards.** OSC 1337 `SetUserVar` is an iTerm2/WezTerm extension.
Emitting it blind sprays base64 into terminals that do not understand it, so
everything except OSC 7 is guarded on WezTerm. OSC 7 is standard and safe
anywhere.

**Percent-encoding.** OSC 7 carries a `file://` URI, so `$PWD` has to be
encoded. Emitting it raw is the usual way to get this wrong: any directory
with a space, and on macOS that includes `Application Support`, produces a
malformed URI and the new split silently lands somewhere else. Encoding is
byte-wise, so multibyte characters become one escape per UTF-8 byte as RFC
3986 requires. There is a fast path for all-unreserved paths, since this runs
on every directory change.

**Hook ordering.** `$?` is clobbered by whichever `precmd` hook runs first, and
oh-my-zsh registers several of its own before plugins load. `add-zsh-hook`
appends, so a naive registration means `D;<status>` reports the exit status of
the last hook rather than of the command you ran. Registration moves the OSC
133 hook to the front of `precmd_functions` to fix that, which is also why this
plugin should load after anything else that hooks `precmd`.

**Interactive only.** Hooks are installed only in an interactive shell. A shell
with no prompt has no use for `precmd` and `preexec`.

**oh-my-zsh's `termsupport`.** It auto-titles every tab from `precmd`/`preexec`,
and because it treats WezTerm as a known terminal its case fires
unconditionally. If you title tabs yourself, set `DISABLE_AUTO_TITLE=true` or
it will clobber you within a second or two.

## Licence

MIT
