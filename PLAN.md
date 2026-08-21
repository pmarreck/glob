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
- [ ] Publish `pmarreck/glob` on `yolo` and verify the exact commit remotely.
  - Curiosity poke: a successful push does not independently prove the remote ref matches.
- [ ] Provision the webhook and verify exact-commit `PASSING` in Mechatron Prime.
  - Curiosity poke: the global worker queue may delay this repo behind unrelated builds.
