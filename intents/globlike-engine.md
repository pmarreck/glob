# Globlike engine migration

Status: accepted by Peter on October 28, 2026.

## Outcome

`glob` consumes the separately maintained `globlike` repository as its only
pattern parser and matcher. The CLI retains ownership of filesystem traversal,
brace expansion, command execution, output formatting, batching, and user-facing
diagnostics.

## Boundaries

- Pin an obtainable `globlike` revision through the Nix flake and build it from
  source inside the sandbox.
- Do not depend on a sibling checkout, ambient Zig cache, or host-installed
  library.
- Do not translate glob or extended-glob syntax into regex in Bash or another
  local compatibility layer.
- Preserve existing CLI behavior unless Peter separately approves a breaking
  change. New `globlike` syntax such as `%r{...}` may be exposed once the shared
  engine is active.
- Keep Unix filesystem and process behavior in this repository; keep the shared
  library pure and in-memory.

## Acceptance evidence

- A test observed failing against the Bash engine proves `%r` inline regex is
  routed through `globlike` after the migration.
- Existing direct, command, brace, recursive, hidden-file, case, extended-glob,
  output, batching, and error contracts remain green.
- Tests prove invalid shared-language patterns remain errors rather than silent
  nonmatches.
- `./test`, `./build`, packaged `glob --test`, and every selected Nix check pass
  without access to `../globlike`.
- The exact pushed commit passes Mechatron Prime.

## Current dependency

`globlike` 0.3.0 at `5976ebd6a353c9e508aa55b7e11cd18d7a10bdc7`
provides the matcher, `%r` sigils, and the CLI's characterized Bash
extended-glob forms. The flake and lock file pin that exact public revision.
