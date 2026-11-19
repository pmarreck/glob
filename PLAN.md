# PLAN

See [completed history](docs/PLAN_LOG.md), [project intent](INTENT.md), and [terminology](TERMINOLOGY.md).

## Bounded directory traversal

- [x] Reproduce the slow single-component glob, bound traversal to the pattern's possible depth/root, and enforce the work bound with independent directory syscall traces. (context: docs/traversal-performance.md; done 2026-11-19 11:10 EST; commit: this commit)

## Standalone native executable

- [x] Port the characterized CLI adapter into the Zig executable and retire the Bash wrapper, sidecar engine, `GLOB_ENGINE`, and ambient Bash-option inheritance. (done 2026-11-19 10:33 EST; commit: this commit)
- [x] Publish the native host executable through `./build`, prove Linux static linkage and no runtime PATH/Nix dependency, then pass the complete package suite. (done 2026-11-19 10:33 EST; commit: this commit)
- [x] Add the general build-product runtime-independence contract and gates to `writing-nix`, with language skills routing to that authority where relevant. (done 2026-11-19 10:39 EST; commit f931d2b)
