# PLAN

See [completed history](docs/PLAN_LOG.md), [project intent](INTENT.md), and [terminology](TERMINOLOGY.md).

## Globlike engine migration

- [x] Add a Nix-built filesystem adapter that pins and invokes `globlike` as the sole matcher while preserving current CLI behavior (completed 2026-10-28; context: intents/globlike-engine.md).
- [x] Preserve the characterized extended-glob contract in `globlike` and pin its tested commit without a local grammar fork (completed 2026-10-28 at globlike `5976ebd`; context: intents/globlike-engine.md).
- [ ] Remove the Bash matching helper after source-tree and packaged regression suites pass, then publish and verify the exact commit (context: intents/globlike-engine.md).
