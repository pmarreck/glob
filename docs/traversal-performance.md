# Bounded pathname traversal

The November 19, 2026 regression was in the filesystem adapter. Every pattern
recursively walked the entire tree, and the dotfile advisory repeated the walk.
A single-component `mecha*` therefore paid for every repository below the
working directory. The matching library was not the bottleneck.

Ordinary glob traversal now has a conservative root and maximum path depth.
Literal directory prefixes are opened directly when matching is case-sensitive.
The selective walker does not enter directories past the possible depth.
Globstar, regex excerpts, and extglobs that may repeat path separators retain
recursive traversal. `globlike` still makes every matching decision. Dotfile
advisories are collected in the same pass, and only matching paths are retained.

## Measurements

Fresh whole-process Hyperfine measurements on Linux amd64, using the static
ReleaseFast package and the same directory with eight results:

| CPU affinity | Before, mean ± SD | After, mean ± SD |
| --- | --- | --- |
| 1 core | 11.603 ± 0.472 seconds | 2.5 ± 0.4 milliseconds |
| 12 cores available | 10.709 ± 0.099 seconds | 2.9 ± 0.7 milliseconds |

The before sample used three runs per case; after used twenty runs and one
warmup. Whole-process wall time includes startup and scheduling. This is a
local observation, not a universal latency guarantee or a historical baseline.
Both versions returned the same eight paths. The original unpinned three-run
baseline averaged 11.291 seconds, including 10.096 seconds of kernel time.
SIMD was considered and deferred because directory I/O dominated the workload.

Reproduce outside the Nix build sandbox, with the exact artifact and workload:

```sh
hyperfine --shell=none --warmup 1 --runs 20 \
  'taskset -c 0 /absolute/path/to/glob mecha*' \
  'taskset -c 0-11 /absolute/path/to/glob mecha*'
```

## Blocking regression check

`./test` includes `tests/cli/traversal_test`. On Linux it uses `strace` as an
independent oracle of directory reads, checking both the directory set and the
number of completed scans. `mecha*` must enumerate only its root once, before
and after adding unrelated descendants. Literal-prefix and fixed-depth cases
have explicit directory sets. The fixture also verifies matching results,
including recursive regex and extglob cases, so skipping required work fails.

This deterministic work bound is the acceptance gate; CI does not accept or
reject machines based on the local millisecond timing. The syscall gate is
Linux-specific; the result checks also run on macOS.
