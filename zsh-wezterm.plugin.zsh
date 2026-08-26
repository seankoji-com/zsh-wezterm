# zsh-wezterm — shell integration for WezTerm.
#
# WezTerm ships integration for bash and fish. This is the zsh equivalent:
#
#   OSC 7    tells the terminal your current directory, so new splits and tabs
#            open where the pane they spawned from was
#   OSC 133  marks prompt, command and output boundaries, so ScrollToPrompt
#            works and each command's output is a selectable semantic zone
#   user var repo_name, so the tab bar can title and colour tabs by repository
#   user var busy, so the tab bar can show which panes are mid-command
#
# Everything except OSC 7 is guarded to WezTerm. OSC 1337 SetUserVar is an
# iTerm2/WezTerm extension and prints base64 garbage in terminals that do not
# know it. OSC 7 is standard and safe to emit anywhere.
#
# Configuration, all default on. Set to 0 before the plugin loads to disable:
#   ZSH_WEZTERM_OSC7        current-directory reporting
#   ZSH_WEZTERM_OSC133      semantic prompt zones
#   ZSH_WEZTERM_REPO_NAME   the repo_name user var
#   ZSH_WEZTERM_BUSY        the busy user var

: ${ZSH_WEZTERM_OSC7:=1}
: ${ZSH_WEZTERM_OSC133:=1}
: ${ZSH_WEZTERM_REPO_NAME:=1}
: ${ZSH_WEZTERM_BUSY:=1}

autoload -Uz add-zsh-hook

# --- helpers ----------------------------------------------------------------

# True when the current terminal is WezTerm.
wezterm_is_wezterm() {
  [[ "$TERM_PROGRAM" == "WezTerm" || -n "$WEZTERM_EXECUTABLE" || -n "$WEZTERM_PANE" ]]
}

# Percent-encode a path for use in a file:// URI.
#
# Emitting $PWD raw is the common way to get this wrong: any directory with a
# space in it, and on macOS that includes "Application Support", produces a
# malformed URI and the new split silently lands somewhere else.
#
# Encoding is byte-wise so multibyte characters become one escape per UTF-8
# byte, which is what RFC 3986 asks for. The fast path returns untouched for
# the overwhelmingly common all-unreserved case, since this runs on every
# directory change.
#
# no_multibyte rather than LC_ALL=C: assigning the locale does not reliably
# flip zsh into byte semantics for a string it has already parsed, and the
# result then differs between a UTF-8 and a C locale. no_multibyte is the
# explicit switch and gives identical output under any locale.
wezterm_urlencode() {
  local str=$1 out='' i
  if [[ $str != *[^a-zA-Z0-9/._~-]* ]]; then
    print -rn -- $str
    return
  fi
  setopt localoptions no_multibyte
  for (( i = 1; i <= ${#str}; i++ )); do
    case $str[i] in
      ([a-zA-Z0-9/._~-]) out+=$str[i] ;;
      (*) out+="%${(l:2::0:)$(( [##16] ##$str[i] ))}" ;;
    esac
  done
  print -rn -- $out
}

# Set a WezTerm user var, readable in wezterm.lua as pane.user_vars.<name>.
# Values are base64-encoded, which is what the OSC 1337 SetUserVar form wants.
# Public: other plugins and functions can use this to publish their own state.
# Returns 0 when it declines to emit: being in another terminal is a normal
# condition, not a failure, and callers should not have to special-case it.
wezterm_set_user_var() {
  [[ -t 1 ]] || return 0
  wezterm_is_wezterm || return 0
  printf '\033]1337;SetUserVar=%s=%s\007' \
    "$1" "$(printf '%s' "$2" | base64 | tr -d '\n')"
}

# The repository name for the current directory, empty outside a repo.
# Prefers the origin remote's name, which stays correct inside a worktree
# where the directory is named after the branch rather than the project.
# Public: used by the repo_name hook, and useful on its own in a prompt.
wezterm_repo_name() {
  local top url name=''
  if top=$(command git rev-parse --show-toplevel 2>/dev/null); then
    if url=$(command git remote get-url origin 2>/dev/null) && [[ -n "$url" ]]; then
      name=${url##*/}
      name=${name%.git}
    else
      name=${top##*/}
    fi
  fi
  print -r -- "$name"
}

# --- hooks ------------------------------------------------------------------

_wezterm_osc7() {
  [[ -t 1 ]] || return
  printf '\033]7;file://%s%s\033\\' "${HOST}" "$(wezterm_urlencode "$PWD")"
}

_wezterm_repo_name_hook() {
  wezterm_set_user_var repo_name "$(wezterm_repo_name)"
}

_wezterm_osc133_precmd() {
  local st=$?
  [[ -t 1 ]] || return
  wezterm_is_wezterm || return
  # Only report a status if a command actually ran. Otherwise the first prompt
  # of a session reports a D;0 for a command that never happened.
  (( ${_wezterm_cmd_ran:-0} )) && printf '\033]133;D;%d\033\\' "$st"
  _wezterm_cmd_ran=0
  printf '\033]133;A\033\\'
  (( ZSH_WEZTERM_BUSY )) && wezterm_set_user_var busy 0
}

_wezterm_osc133_preexec() {
  [[ -t 1 ]] || return
  wezterm_is_wezterm || return
  _wezterm_cmd_ran=1
  printf '\033]133;C\033\\'
  (( ZSH_WEZTERM_BUSY )) && wezterm_set_user_var busy 1
}

# --- registration -----------------------------------------------------------

# Split out from the load path so it can be called deliberately. A shell with
# no prompt has no use for precmd and preexec hooks, and installing them
# unconditionally also breaks test harnesses that drive their own hooks.
zsh_wezterm_register() {
  if (( ZSH_WEZTERM_OSC7 )); then
    add-zsh-hook chpwd _wezterm_osc7
    _wezterm_osc7
  fi

  if (( ZSH_WEZTERM_REPO_NAME )); then
    add-zsh-hook chpwd _wezterm_repo_name_hook
    _wezterm_repo_name_hook
  fi

  if (( ZSH_WEZTERM_OSC133 )); then
    add-zsh-hook precmd _wezterm_osc133_precmd
    add-zsh-hook preexec _wezterm_osc133_preexec

    # add-zsh-hook appends, but $? is clobbered by whichever precmd hook runs
    # first, and oh-my-zsh registers several of its own before plugins load.
    # Without this, D;<status> reports the exit status of the last hook rather
    # than of the command the user ran. Move ours to the front.
    precmd_functions=(_wezterm_osc133_precmd ${precmd_functions:#_wezterm_osc133_precmd})
  fi
}

# `if`, not `&&`: a bare `[[ ... ]] && cmd` makes the whole file exit non-zero
# when the guard is false, so `source`ing it reports failure to the caller.
if [[ -o interactive ]]; then
  zsh_wezterm_register
fi
