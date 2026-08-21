# Project overview

`glob` makes pathname expansion an explicit command. It accepts quoted Bash
patterns, prints their matches in deterministic code-point order, or expands
patterns into the argument list of another command.

The project preserves the behavior of Peter Marreck's original dotfiles
utility while removing dependencies on the rest of the dotfiles tree. It is a
Bash 4+ command for Unix-like systems, packaged reproducibly with Nix.

Terms used here:

- Direct mode prints expanded paths.
- Command mode runs the first executable argument with subsequent patterns
  expanded in place.
- Code-point order means `LC_ALL=C` byte order, independent of the caller's
  locale.
- Explicit globbing means the caller quotes patterns and asks `glob` to expand
  them, usually while the interactive shell has automatic expansion disabled
  with `set -f`.
