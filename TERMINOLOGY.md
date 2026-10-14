# Terminology

- **Direct mode:** Print expanded paths.
- **Command mode:** Run the first executable argument with subsequent patterns
  expanded in place.
- **Code-point order:** `LC_ALL=C` byte order, independent of the caller's
  locale.
- **Explicit globbing:** Quote patterns and ask `glob` to expand them, usually
  while the interactive shell has automatic expansion disabled with `set -f`.
