# Plan

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
- [ ] Verify exact-commit `PASSING` in Mechatron Prime.
  - Retry checkpoint: `ff621ea` was claimed, then its GitHub flake prefetch hung in `CLOSE-WAIT`. A worker restart exhausted its stop timeout, and redelivering the same signed push was correctly deduplicated. This content commit creates the fresh signed push event for exact-SHA verification.
  - Curiosity poke: the global worker queue may delay this repo behind unrelated builds.
