# glob

[![Mechatron Prime CI](https://img.shields.io/endpoint?url=https%3A%2F%2Fthelio-nixos.tail66c90.ts.net%2Fbadges%2Fglob.json&style=for-the-badge)](https://thelio-nixos.tail66c90.ts.net/mechatron-prime/)

`glob` makes shell pathname expansion an explicit operation. Give it quoted
patterns to print deterministic matches, or put a command first to expand
patterns into that command's argument list. Its sole matching engine is
[`globlike`](https://github.com/pmarreck/globlike); this project supplies the
filesystem traversal, command execution, and output-format adapters around it
in one native executable.

```console
$ set -f
$ glob '*.{jpg,png}'
cover.jpg
diagram.png

$ glob printf '<%s>\n' 'drafts/**/*.md'
<drafts/notes/one.md>
<drafts/notes/two.md>
```

## Why make globbing explicit?

Peter's design opinion is that implicit, default shell glob expansion was a
mistake. The shell rewrites unquoted metacharacters before the command sees its
arguments, which makes quoting and non-match behavior easy to overlook. With
automatic expansion disabled (`set -f`), quoted patterns remain data until a
visible `glob` command expands them. That makes the expansion site, output
format, case handling, hidden-file policy, and failure behavior reviewable.

This is a design argument, not a claim that early Unix users normally invoked
`glob` themselves.

## The early Unix name

First Edition Unix already used a separate `/etc/glob` program. The V1
[`sh(1)` manual](https://www.tuhs.org/cgi-bin/utree.pl?file=V1%2Fman%2Fman1%2Fsh.1)
says the shell invoked the glob routine when an argument contained `*` or `?`,
and lists `/etc/glob` under FILES. Pathname expansion was therefore
shell-triggered and implicit/default in V1 even though the implementation lived
in another executable.

The June 15, 1972
[`glob` manual](https://www.tuhs.org/cgi-bin/utree.pl?file=V10%2Fdist%2Fman%2Fv3%2Fman7%2Fglob.7)
describes `/etc/glob` receiving the metacharacter-bearing argument list,
expanding it, and calling the requested command. The
[`V6 shell source`](https://www.tuhs.org/cgi-bin/utree.pl?file=V6%2Fusr%2Fsource%2Fs2%2Fsh.c)
still visibly executes `/etc/glob`. By V7, the
[`Unix beginner's tutorial`](https://www.tuhs.org/cgi-bin/utree.pl?file=V7M%2Fdoc%2Fbeginners%2Fu2)
describes the shell itself translating `*` into a filename list.

This project reuses the old program name and the separate-executable shape. Its
explicit invocation model is Peter's present-day preference.

## Install

Run without installing:

```console
nix run github:pmarreck/glob -- '*.jpg'
```

Install into a Nix profile:

```console
nix profile install github:pmarreck/glob
```

For development, `nix develop` supplies Bash, Zig, LuaJIT, and ShellCheck. Nix
is the reproducible build environment, not a runtime dependency: the Linux
package is a static native executable with `globlike` and PCRE2 linked into it.
It needs no Bash wrapper, sidecar engine, Nix installation, or `/nix/store`
path to expand patterns. It does not depend on Peter's dotfiles or carry a
second glob parser or translator.

## Usage

```text
glob [OPTIONS] PATTERN...
glob [OPTIONS] COMMAND [ARG...]
```

Options:

- `-i`, `--ignore-case`: case-insensitive matching.
- `--dotglob`, `--dotfiles`, `--all`: include hidden files.
- `--hidden`: alias for `--dotglob` and `--dotfiles`.
- `--gitignore`, `--gitignored`: include paths excluded by `.gitignore` files.
- `--mute`: silence exclusion summaries; errors and child stderr remain visible.
- `--batch`: split command execution into ARG_MAX-safe chunks.
- `--dry-run`, `--debug`: print the expanded command without running it.
- `--double-quote`: quote each newline-separated result and escape `"`.
- `-n`: emit shell-escaped results separated by spaces.
- `-0`: emit NUL-separated results.
- `-h`, `--help`: show command help.
- `--about`: show version and immutable compiled platform/ABI identity.

Patterns support `*`, `?`, bracket expressions, `**`, `%r{...}` inline regex
excerpts, quoted brace expansion, and extended globs such as
`@(*.jpg|*.png)`. The matching syntax comes from `globlike`; brace expansion
remains a CLI adapter concern. Non-matching patterns are omitted. Direct mode
exits 1 if nothing matches. Command mode preserves the caller's argument order
while sorting each pattern's matches with `LC_ALL=C`.

Hidden paths and `.gitignore` exclusions are respected by default. Directories
excluded by either policy are pruned before reading their contents. A pattern
that explicitly names a hidden component can still access it.

Use `--hidden` (also `--dotglob` or `--dotfiles`) for hidden paths,
`--gitignore` or `--gitignored` for gitignored paths, and `--all` for both.
These switches are independent. Private option state in a parent Bash process
does not cross the native executable boundary.

After results or child-command execution, `glob: ` summaries on stderr report
unique excluded matching entries and pruned directory frontiers, with the
override needed to include them. A pruned directory counts once: descendants
are not scanned merely to count missing matches. `--mute` suppresses these
summaries without changing results or silencing errors. Child stderr is passed
through unchanged; every line generated by glob itself starts with `glob: `.

Ignore rules come from ancestor and nested `.gitignore` files, with nested
repository boundaries, last-rule precedence, negation, directory-only and
anchored patterns. Rule evaluation does not consult Git's index: like a file
finder, it applies patterns even to tracked files. Rules also work outside Git
repositories. Global Git configuration, `.git/info/exclude`, `.ignore`, and
`.fdignore` are not read. See [Git's pattern reference](https://git-scm.com/docs/gitignore).
Git is used only as a differential test oracle, never as a runtime dependency.

Paths containing newline characters are not supported. Use `-0` when ordinary
whitespace or shell punctuation makes newline-separated output inconvenient.

[`cols`](https://github.com/pmarreck/cols) is Peter's companion command for
explicitly selecting fields from line-oriented output.

## Development

```console
./test          # isolated CLI characterization suite
./build         # Nix package and publish the native host command
./build --test  # every Nix flake check
```

The standalone suite was ported before the implementation. It runs the exact
packaged executable, checks Linux static linkage and absence of Nix-store
references, and covers pattern
sets, command ordering, recursive and extended patterns, hidden files, case
folding, all output formats, dry runs, help, and the absence of a `compgen`
dependency.

Ordinary pathname globs scan only their possible path depth, starting at a
literal directory prefix when one is available. `glob 'mecha*'` reads the
current directory once without opening its descendants. Recursive patterns and
regex excerpts retain recursive traversal. Linux tests inspect kernel directory
syscalls to enforce that work bound; see [performance evidence](docs/traversal-performance.md).

The exclusion suite additionally checks results against `git check-ignore`
and verifies that hidden and gitignored subtrees are never enumerated by
default. Override, summary-count, command-stderr, and `--mute` cases all run
through `./test` and the Nix check.

Licensed under the [MIT License](LICENSE).
