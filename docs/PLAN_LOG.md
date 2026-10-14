# PLAN Log

Completed work retired from `PLAN.md`.

## Retired 2026-10-14

- [x] [Plan] Make `bin/glob` the canonical source-tree executable while preserving `$out/bin/glob` in the installed package. Completed 2026-08-21 04:10 PM EDT: the source executable moved under `bin/`, checkout and installed `--test` discovery both work, and the Nix package plus complete flake check pass. Packaging follow-up completed 2026-08-21 04:20 PM EDT: an in-sandbox package smoke test caught both an unpatched `/usr/bin/env` shebang and `wrapProgram` dropping caller `bash -O dotglob` state. The installed script now carries an immutable runtime PATH directly and runs its full packaged self-test without a wrapper process.
  - Curiosity poke: `--test` must work both from a checkout and from the immutable Nix package without assuming the old repository layout.
- [x] [Plan] Import the remaining dotfiles regression coverage, prove it passes against the standalone implementation, then remove the duplicate dotfiles executable, helper, and tests. Import completed 2026-08-21 04:10 PM EDT: 18 standalone cases, the legacy 64/66-case platform-dependent contract, and three stripped-Bash/isolation cases pass both on the host and in the Nix sandbox. Completed 2026-08-21 04:25 PM EDT: dotfiles commit `b64ecc6` removed all four legacy files, pins this package for its sandbox/dev shell, passed 178 host tests, 131 hermetic tests, and its 178-test pre-push gate. Fresh shells use this repository's `bin/glob` directly.
  - Curiosity poke: fresh interactive shells must resolve `glob` through `.pathconfig`'s `~/Code/*/bin` discovery and never a stale Bash hash entry.
- [x] [Plan] Port the dotfiles behavior into isolated characterization tests. (2026-08-21 02:50 PM EDT)
  - Curiosity poke: filenames can contain spaces, quotes, newlines, and leading dashes.
- [x] [Plan] Package the existing Bash implementation without dotfiles dependencies. (2026-08-21 02:50 PM EDT)
  - Curiosity poke: `#!/usr/bin/env bash` needs patching inside the Nix sandbox.
- [x] [Plan] Add `--about`, standalone help, and clean `./test` and `./build` entrypoints. (2026-08-21 02:52 PM EDT)
  - Curiosity poke: interpreted scripts report runtime OS/architecture rather than a compile target.
- [x] [Plan] Add the pinned Nix flake, package, check, and LuaJIT development shell. (2026-08-21 02:52 PM EDT)
  - Curiosity poke: CI must realize intentional outputs, not merely evaluate them.
- [x] [Plan] Document the design opinion and early-Unix history with direct primary-source citations. (2026-08-21 02:52 PM EDT)
  - Curiosity poke: early `/etc/glob` was separate, but pathname expansion was already shell-triggered in V1.
- [x] [Plan] Publish `pmarreck/glob` on `yolo` and verify the exact commit remotely. (2026-08-21 02:55 PM EDT)
  - Curiosity poke: a successful push does not independently prove the remote ref matches.
- [x] [Plan] Provision and inspect the canonical push webhook. (2026-08-21 03:00 PM EDT)
- [x] [Plan] Verify exact-commit `PASSING` in Mechatron Prime. (2026-08-21 03:26 PM EDT; `03785f49e67f736f0af30e8800c0aac73d5cbb2a` passed in 46 seconds)
  - Retry checkpoint: `ff621ea` was claimed, then its GitHub flake prefetch hung in `CLOSE-WAIT`. A worker restart exhausted its stop timeout, and redelivering the same signed push was correctly deduplicated. This content commit creates the fresh signed push event for exact-SHA verification.
  - Curiosity poke: the global worker queue may delay this repo behind unrelated builds.
- [x] [CI onboarding incident] Mechatron Prime bounded source prefetch at 60 seconds, made signal recovery interrupt the in-flight child, added `claim.json` orphan recovery, and tested exactly-once requeue (`9bcfce50e100`; done 2026-09-28 23:26 EDT).
