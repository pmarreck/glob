# Project intent

## Purpose and users

`glob` makes shell pathname expansion an explicit operation. It serves people
who want quoted patterns to remain data until a visible command expands them,
including Peter's shell workflow with automatic expansion disabled.

## Desired outcomes

- Print matches for quoted Bash patterns in deterministic code-point order.
- Expand patterns into another command's argument list without changing the
  caller's argument order.
- Preserve the characterized behavior of Peter's original dotfiles utility in
  a standalone package.
- Keep installation and testing reproducible through Nix.
- Use the separately maintained `globlike` library as the sole pattern-matching
  engine; keep filesystem traversal, command execution, and presentation in this
  CLI's adapters.

## Scope and non-goals

The project is a Bash 4+ command for Unix-like systems. It supports direct and
command modes, the documented output formats, hidden-file and case controls,
recursive patterns, brace expansion, and extended globs.

It does not replace a shell, depend on Peter's dotfiles, or support pathnames
containing newline characters. `group_with_count` remains outside the accepted
scope unless Peter makes a separate explicit decision.

The CLI must not maintain a second glob parser, translator, or matcher alongside
`globlike`. Compatibility syntax needed by this command belongs in the shared
library.

## Constraints

- Preserve the characterized CLI behavior and exit codes.
- Keep expansion independent of Bash programmable completion (`compgen`).
- Keep output ordering independent of the caller's locale.
- Keep the explicit-globbing argument framed as Peter's design opinion, without
  claiming that early Unix users normally invoked `/etc/glob` themselves.

## Success evidence

Success requires the complete `./test` suite and `./build` to pass, the Nix
package to run its own installed tests inside the sandbox, and the selected
flake targets to pass at the exact published commit in Mechatron Prime.

See [TERMINOLOGY.md](TERMINOLOGY.md) for project terms, [PLAN.md](PLAN.md) for
active work, and [README.md](README.md) for the user-facing interface and
historical sources. The accepted engine migration is specified in
[intents/globlike-engine.md](intents/globlike-engine.md).
