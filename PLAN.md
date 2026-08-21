# Plan

- [x] Make `bin/glob` the canonical source-tree executable while preserving
  `$out/bin/glob` in the installed package.
  Completed 2026-08-21 04:10 PM EDT: the source executable moved under
  `bin/`, checkout and installed `--test` discovery both work, and the Nix
  package plus complete flake check pass.
  - Curiosity poke: `--test` must work both from a checkout and from the
    immutable Nix package without assuming the old repository layout.
- [ ] Import the remaining dotfiles regression coverage, prove it passes
  against the standalone implementation, then remove the duplicate dotfiles
  executable, helper, and tests.
  Import completed 2026-08-21 04:10 PM EDT: 18 standalone cases, the legacy
  64/66-case platform-dependent contract, and three stripped-Bash/isolation
  cases pass both on the host and in the Nix sandbox. Dotfiles removal remains.
  - Curiosity poke: fresh interactive shells must resolve `glob` through
    `.pathconfig`'s `~/Code/*/bin` discovery and never a stale Bash hash entry.

- [x] Port the dotfiles behavior into isolated characterization tests. (2026-08-21 02:50 PM EDT)
  - Curiosity poke: filenames can contain spaces, quotes, newlines, and leading dashes.
- [x] Package the existing Bash implementation without dotfiles dependencies. (2026-08-21 02:50 PM EDT)
  - Curiosity poke: `#!/usr/bin/env bash` needs patching inside the Nix sandbox.
- [x] Add `--about`, standalone help, and clean `./test` and `./build` entrypoints. (2026-08-21 02:52 PM EDT)
  - Curiosity poke: interpreted scripts report runtime OS/architecture rather than a compile target.
- [x] Add the pinned Nix flake, package, check, and LuaJIT development shell. (2026-08-21 02:52 PM EDT)
  - Curiosity poke: CI must realize intentional outputs, not merely evaluate them.
- [x] Document the design opinion and early-Unix history with direct primary-source citations. (2026-08-21 02:52 PM EDT)
  - Curiosity poke: early `/etc/glob` was separate, but pathname expansion was already shell-triggered in V1.
- [x] Publish `pmarreck/glob` on `yolo` and verify the exact commit remotely. (2026-08-21 02:55 PM EDT)
  - Curiosity poke: a successful push does not independently prove the remote ref matches.
- [x] Provision and inspect the canonical push webhook. (2026-08-21 03:00 PM EDT)
- [x] Verify exact-commit `PASSING` in Mechatron Prime. (2026-08-21 03:26 PM EDT; `03785f49e67f736f0af30e8800c0aac73d5cbb2a` passed in 46 seconds)
  - Retry checkpoint: `ff621ea` was claimed, then its GitHub flake prefetch hung in `CLOSE-WAIT`. A worker restart exhausted its stop timeout, and redelivering the same signed push was correctly deduplicated. This content commit creates the fresh signed push event for exact-SHA verification.
  - Curiosity poke: the global worker queue may delay this repo behind unrelated builds.
