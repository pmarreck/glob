# Rules

- Preserve the characterized CLI behavior and exit codes.
- Keep expansion independent of Bash programmable completion (`compgen`).
- Keep output ordering independent of the caller's locale.
- Keep command-mode argument order intact.
- Keep the standalone package independent of Peter's dotfiles.
- Use pinned `globlike` as the sole pattern-matching engine; do not duplicate its
  parser or translator in this repository.
- Run `./test` and `./build` before every commit.
- Do not claim that early Unix users normally invoked `/etc/glob` explicitly.
- Do not implement `group_with_count` without a separate, explicit decision.
