# shellcheck shell=bash disable=all
# Guard checks and OSC emission are zsh-specific, so this suite runs under
# shellspec's zsh mode rather than bats.
Describe 'zsh-wezterm.plugin.zsh'
  # ./ prefix required: a bare name is PATH-searched by `.` and never found.
  # Sourcing here installs no hooks: registration is gated on an interactive
  # shell, and the registration block below invokes it explicitly.
  Include ./zsh-wezterm.plugin.zsh

  Describe 'wezterm_urlencode'
    It 'leaves an all-unreserved path untouched'
      When call wezterm_urlencode '/Users/x/plain/path-1_2.3~4'
      The output should equal '/Users/x/plain/path-1_2.3~4'
    End

    # macOS paths routinely contain spaces. Emitting one raw produces a
    # malformed file:// URI and the new split lands in the wrong directory.
    It 'encodes a space'
      When call wezterm_urlencode '/Users/x/Application Support/y'
      The output should equal '/Users/x/Application%20Support/y'
    End

    It 'encodes characters that would break the URI'
      When call wezterm_urlencode '/a/b#c?d e'
      The output should equal '/a/b%23c%3Fd%20e'
    End

    # RFC 3986 wants one escape per byte, not per character.
    #
    # $'...' rather than "$(printf '\xc3\xa9')": the command substitution is
    # resolved by whichever printf the runner provides, and on Ubuntu it
    # produced two spaces instead of the two bytes, so this passed on macOS and
    # failed in CI. The zsh literal has no such ambiguity.
    It 'encodes a multibyte character as its UTF-8 bytes'
      When call wezterm_urlencode $'/Users/x/caf\xc3\xa9'
      The output should equal '/Users/x/caf%C3%A9'
    End

    It 'encodes a 3-byte character as three escapes'
      When call wezterm_urlencode $'/x/\xe2\x9c\x93'
      The output should equal '/x/%E2%9C%93'
    End

    It 'handles an empty string'
      When call wezterm_urlencode ''
      The output should equal ''
    End
  End

  Describe 'wezterm_is_wezterm'
    It 'is true when TERM_PROGRAM says WezTerm'
      run_it() { TERM_PROGRAM=WezTerm WEZTERM_EXECUTABLE='' WEZTERM_PANE='' wezterm_is_wezterm; }
      When call run_it
      The status should be success
    End

    It 'is true when only WEZTERM_PANE is set'
      run_it() { TERM_PROGRAM=xterm WEZTERM_EXECUTABLE='' WEZTERM_PANE=3 wezterm_is_wezterm; }
      When call run_it
      The status should be success
    End

    It 'is false in another terminal'
      run_it() { TERM_PROGRAM=iTerm.app WEZTERM_EXECUTABLE='' WEZTERM_PANE='' wezterm_is_wezterm; }
      When call run_it
      The status should be failure
    End
  End

  Describe 'wezterm_set_user_var'
    # OSC 1337 SetUserVar is an iTerm2/WezTerm extension. Emitting it blind
    # sprays base64 into terminals that do not understand it.
    It 'emits nothing in a non-WezTerm terminal'
      run_it() { TERM_PROGRAM=xterm WEZTERM_EXECUTABLE='' WEZTERM_PANE='' wezterm_set_user_var k v; }
      When call run_it
      The output should equal ''
      # Declining is a normal outcome, not an error: callers must not have to
      # special-case running under a different terminal.
      The status should be success
    End

    It 'emits nothing when stdout is not a terminal'
      # shellspec's stdout is a pipe, so the -t 1 guard holds even with the
      # WezTerm environment set.
      run_it() { TERM_PROGRAM=WezTerm wezterm_set_user_var k v; }
      When call run_it
      The output should equal ''
      The status should be success
    End
  End

  Describe 'wezterm_repo_name'
    # Real repositories rather than a git() stub: the implementation calls
    # `command git` on purpose, to step over any git wrapper the user has
    # defined, and `command` steps over shell function mocks too.
    setup() { TMPROOT="$(mktemp -d)"; }
    cleanup() { rm -rf "$TMPROOT"; builtin cd "$SHELLSPEC_PROJECT_ROOT"; }
    BeforeEach 'setup'
    AfterEach 'cleanup'

    make_repo() {
      # $1 directory name, $2 optional origin URL
      mkdir -p "$TMPROOT/$1"
      git -C "$TMPROOT/$1" init -q
      [[ -n "$2" ]] && git -C "$TMPROOT/$1" remote add origin "$2"
      builtin cd "$TMPROOT/$1"
    }

    It 'is empty outside a git repository'
      run_it() { builtin cd "$TMPROOT"; wezterm_repo_name; }
      When call run_it
      The output should equal ''
    End

    # Inside a worktree the directory is named after the branch, so the remote
    # is the only thing that still identifies the project.
    It 'prefers the origin remote name over the directory name'
      run_it() { make_repo feature-branch-dir 'git@github.com:acme/widgets.git'; wezterm_repo_name; }
      When call run_it
      The output should equal 'widgets'
    End

    It 'strips the .git suffix from an https remote'
      run_it() { make_repo somedir 'https://github.com/acme/widgets.git'; wezterm_repo_name; }
      When call run_it
      The output should equal 'widgets'
    End

    It 'handles a remote with no .git suffix'
      run_it() { make_repo somedir 'https://github.com/acme/widgets'; wezterm_repo_name; }
      When call run_it
      The output should equal 'widgets'
    End

    It 'falls back to the toplevel directory name when there is no origin'
      run_it() { make_repo local-only-repo; wezterm_repo_name; }
      When call run_it
      The output should equal 'local-only-repo'
    End

    It 'reports the repository name from a subdirectory'
      run_it() {
        make_repo widgets-checkout 'https://github.com/acme/widgets.git'
        mkdir -p src/deep && builtin cd src/deep
        wezterm_repo_name
      }
      When call run_it
      The output should equal 'widgets'
    End
  End

  Describe 'zsh_wezterm_register'
    It 'puts the OSC 133 precmd hook first'
      # $? is clobbered by whichever precmd hook runs first, and oh-my-zsh
      # registers several before plugins load. Ours has to lead or D;<status>
      # reports the wrong exit code.
      run_it() {
        precmd_functions=(some_other_hook)
        zsh_wezterm_register
        print -r -- "${precmd_functions[1]}"
      }
      When call run_it
      The output should equal '_wezterm_osc133_precmd'
    End

    It 'keeps hooks that were already registered'
      run_it() {
        precmd_functions=(some_other_hook)
        zsh_wezterm_register
        print -r -- "${precmd_functions[(r)some_other_hook]}"
      }
      When call run_it
      The output should equal 'some_other_hook'
    End

    It 'registers both chpwd hooks'
      run_it() {
        chpwd_functions=()
        zsh_wezterm_register
        print -r -- "${chpwd_functions[(r)_wezterm_osc7]}"
        print -r -- "${chpwd_functions[(r)_wezterm_repo_name_hook]}"
      }
      When call run_it
      The line 1 of output should equal '_wezterm_osc7'
      The line 2 of output should equal '_wezterm_repo_name_hook'
    End

    It 'skips a component that has been switched off'
      run_it() {
        chpwd_functions=()
        ZSH_WEZTERM_OSC7=0 zsh_wezterm_register
        print -r -- "[${chpwd_functions[(r)_wezterm_osc7]}]"
      }
      When call run_it
      The output should equal '[]'
    End

    # Installing prompt hooks in a shell with no prompt is pure overhead, and
    # it breaks harnesses that drive their own precmd chain.
    It 'is not called automatically in a non-interactive shell'
      run_it() { print -r -- "[${precmd_functions[(r)_wezterm_osc133_precmd]}]"; }
      When call run_it
      The output should equal '[]'
    End
  End
End
