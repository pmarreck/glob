# glob

[![Mechatron Prime CI](https://img.shields.io/endpoint?url=https%3A%2F%2Fthelio-nixos.tail66c90.ts.net%2Fbadges%2Fglob.json&style=for-the-badge)](https://thelio-nixos.tail66c90.ts.net/mechatron-prime/)

`glob` makes shell pathname expansion an explicit operation. Give it quoted
patterns to print deterministic matches, or put a command first to expand
patterns into that command's argument list. Its sole matching engine is
[`globlike`](https://github.com/pmarreck/globlike); this project supplies the
filesystem traversal, command execution, and output-format adapters around it.

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

For development, `nix develop` supplies Bash, Zig, LuaJIT, and ShellCheck. The
runtime package contains the Bash command and a Zig filesystem adapter linked
to the separately pinned `globlike` source. It does not depend on Peter's
dotfiles, and it does not carry a second glob parser or translator.

## Usage

```text
glob [OPTIONS] PATTERN...
glob [OPTIONS] COMMAND [ARG...]
```

Options:

- `-i`, `--ignore-case`: case-insensitive matching.
- `--dotglob`, `--dotfiles`, `--all`: include hidden files.
- `--batch`: split command execution into ARG_MAX-safe chunks.
- `--dry-run`, `--debug`: print the expanded command without running it.
- `--double-quote`: quote each newline-separated result and escape `"`.
- `-n`: emit shell-escaped results separated by spaces.
- `-0`: emit NUL-separated results.
- `-h`, `--help`: show command help.
- `--about`: show version, runtime operating system, and architecture.

Patterns support `*`, `?`, bracket expressions, `**`, `%r{...}` inline regex
excerpts, quoted brace expansion, and extended globs such as
`@(*.jpg|*.png)`. The matching syntax comes from `globlike`; brace expansion
remains a CLI adapter concern. Non-matching patterns are omitted. Direct mode
exits 1 if nothing matches. Command mode preserves the caller's argument order
while sorting each pattern's matches with `LC_ALL=C`.

Paths containing newline characters are not supported. Use `-0` when ordinary
whitespace or shell punctuation makes newline-separated output inconvenient.

[`cols`](https://github.com/pmarreck/cols) is Peter's companion command for
explicitly selecting fields from line-oriented output.

## Development

```console
./test          # isolated CLI characterization suite
./build         # Nix package
./build --test  # every Nix flake check
```

The standalone suite was ported before the implementation. It covers pattern
sets, command ordering, recursive and extended patterns, hidden files, case
folding, all output formats, dry runs, help, and the absence of a `compgen`
dependency.

Licensed under the [MIT License](LICENSE).
