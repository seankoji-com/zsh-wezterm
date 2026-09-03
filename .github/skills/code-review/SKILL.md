---
name: code-review
description: Review priorities for zsh-wezterm pull requests, what deserves real scrutiny versus what to skip. Use for every PR review.
---

# Review priorities

zsh-wezterm is one ~160-line plugin file (`zsh-wezterm.plugin.zsh`) that emits
terminal control sequences (OSC 7, OSC 133, OSC 1337) from zsh hooks. Small
surface, high correctness bar: a wrong byte or hook order corrupts a live
terminal session, not a test failure a user can shrug off.

## Spend real attention here

- **Byte-vs-character handling in `wezterm_urlencode`** (and any new code
  built on `no_multibyte` or per-byte iteration). The one substantive
  historical fix here (#1) passed on macOS and failed in Ubuntu CI because
  the encoder's byte semantics were only accidentally correct on the author's
  machine. Check locale/multibyte assumptions, not just "does it pass here."
- **Shellspec fixtures that assert on raw bytes.** Same PR: a fixture built
  with `"$(printf '\xNN')"` is resolved by whichever `printf` the runner
  ships and silently tested the wrong bytes on Ubuntu. A new byte-level
  assertion should use a zsh `$'...'` literal, not command substitution.
- **Hook registration and ordering** in `zsh_wezterm_register`
  (`precmd_functions`/`chpwd_functions` manipulation). `$?` is clobbered by
  whichever `precmd` hook runs first, which is why registration force-reorders
  `precmd_functions`. Check that a change still guarantees the OSC 133 hook
  leads, and that interactive-only gating is preserved.
- **Terminal guards on any new escape-sequence emitter.** Every OSC 133/1337
  emission is gated on `-t 1` and `wezterm_is_wezterm` (OSC 7 only needs the
  first — it's standard and safe unguarded). A new `printf '\033]...'` call
  site that skips these sprays control sequences or base64 into terminals
  that don't understand them.

## Do not spend attention here

- README.md / LICENSE wording and formatting — docs only, no runtime behavior.
- Requests for more comments or rationale — this file already over-documents
  its own edge cases (see its header block and the README's "Notes on the
  fiddly bits"); it doesn't need more of that.
- `.github/workflows/*.yml` in a PR titled like
  `chore(ci): sync caller templates from seankoji-com/.github` — these are
  synced centrally from the org `.github` repo, not organic changes to
  litigate here.
- Whether shellspec passes — `shellspec.yml` runs the full suite on every
  push/PR already. Don't restate what a red check will already say; point at
  what's untested instead.

## Comment style

- One comment per real issue, not one per file it repeats in.
- Skip restating what CI or lint already flags.
