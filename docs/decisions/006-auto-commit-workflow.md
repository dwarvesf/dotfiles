# ADR-006: Auto-commit workflow for dotfile changes

## Status: accepted

## Context

chezmoi separates the **source state** (the repo in `~/.local/share/chezmoi/`) from the **target state** (deployed files in `$HOME`). This two-layer model is powerful but creates a recurring failure mode: you change a config file, it works on your machine, but you forget to commit. Days later you set up a new machine or lose a disk, and the change is gone.

The gap between "applied to my machine" and "backed up in git" is where config changes go to die. In practice, three things go wrong:

1. **Forgot to commit.** You run `chezmoi edit --apply`, the change works, you move on. The source file is modified but never staged or committed.
2. **Edited the wrong layer.** You open `~/.config/fish/config.fish` directly instead of the chezmoi source. The deployed file now differs from the source (drift). Next `chezmoi apply` silently overwrites your change.
3. **Partial commit.** You edit three files, commit one, forget the other two. The repo is in an inconsistent state you won't notice until something breaks.

All three are human memory failures, not technical failures. The tooling should close the loop automatically.

## Decision

Make **commit-on-change the default** for all dotfile editing workflows. Every helper that modifies the chezmoi source tree auto-commits the diff after a successful apply. Push remains manual.

### The helpers

**`dotfiles edit` (dotfile edit)** handles the forward path: source → machine.

```
dotfiles edit ~/.config/fish/config.fish
```

This runs `chezmoi edit --apply` to open the source file in your editor, applies on save, then auto-commits any changed files under `home/`. The commit message is mechanical: `chore(config): update config.fish via dotfiles edit`.

**`dotfiles drift` (dotfile sync)** handles the reverse path: machine → source.

```
dotfiles drift
```

This runs `chezmoi status` to find deployed files that differ from the source (drift), shows you the list, asks for confirmation, then runs `chezmoi re-add` to pull the live versions back into the source tree and commits the result.

**`dotfiles secret add` / `dotfiles secret rm`** modify `.chezmoidata/secrets.toml` (the secret registry) and auto-commit the change.

All four helpers accept `--no-commit` to opt out.

### Why push is manual

Auto-commit is safe because it's local and reversible (`git reset`). Auto-push is not:

- You might be mid-experiment and want to squash commits before pushing.
- A bad config could propagate to other machines that pull automatically.
- Push failures (auth, network) would need retry logic and error handling that doesn't belong in a fish function.

Instead, each helper prints the exact `git push` command after committing so you can run it when ready. This keeps the helpers simple and the blast radius local.

### Why commit is opt-out, not opt-in

The original design had `--commit` as an opt-in flag. This was backwards: the safe default should be "your changes are backed up." Forgetting `--commit` means losing work silently. Forgetting `--no-commit` means at worst an extra commit you can amend or squash.

The cost of a forgotten `--commit` (lost work) is much higher than the cost of a forgotten `--no-commit` (extra commit). So commit is the default.

### The two-direction model

Config drift can happen in either direction:

| Direction | Cause | Tool |
|-----------|-------|------|
| Source → machine | You edit the source, need to apply | `dotfiles edit` |
| Machine → source | You edited the deployed file directly, or an app rewrote its config | `dotfiles drift` |

Together, `dotfiles edit` and `dotfiles drift` cover both directions. The workflow is:

1. **Normal edits**: use `dotfiles edit`. One command: edit, apply, commit.
2. **Accidental direct edits**: run `dotfiles drift` to detect and re-absorb drift.
3. **Secrets**: use `dotfiles secret add` / `dotfiles secret rm`. Same auto-commit behavior.

## Alternatives considered

- **fswatch / file watcher daemon**: Auto-apply on every source file save. Too aggressive; you lose the ability to make multi-file changes before applying. Also requires a background process that can die silently.
- **Git hooks (post-commit apply)**: Couples git operations to chezmoi apply. Breaks when you commit non-chezmoi files. Direction is wrong: we want apply-then-commit, not commit-then-apply.
- **Makefile / justfile targets**: `make apply`, `make sync`. Works but adds a dependency and another tool to remember. Fish functions are discoverable via tab completion and don't require being in the repo directory.
- **chezmoi's built-in git auto-commit**: chezmoi has `git.autoCommit` in its config, but it commits on every `chezmoi apply` including no-op runs, and the commit messages aren't customizable. Our helpers only commit when there are actual changes and produce descriptive messages.

## Consequences

- Every helper that touches source files auto-commits by default. Contributors should expect this.
- Commit messages from helpers follow the pattern `chore(config): ...`. They are mechanical and meant for backup, not human-readable changelogs.
- Push is always manual. No helper will ever run `git push` automatically.
- The `--no-commit` flag is the escape hatch for all helpers when you need to batch changes or are experimenting.
- `dotfiles drift` requires user confirmation before re-absorbing drift. It will never silently overwrite source files.
- The workflow assumes you're working in a git repo. If the dotfiles source isn't a git repo (unlikely but possible), the commit step is silently skipped.

## Exception: the S-64 background watcher (2026-05-12)

[S-64](../specs/S-64-dotfiles-watch.md) ships a pair of LaunchAgents that absorb drift into the repo's working tree continuously, without committing. This is a **deliberate, explicit exception** to the commit-on-change rule above. The Alternatives-considered section originally rejected an "fswatch / file watcher daemon" on two grounds: it would be too aggressive (auto-applying source-to-machine on every save) and could die silently. S-64 sidesteps both concerns by reversing the direction (machine-to-source absorption only, never source-to-machine apply) and by being opt-in (`dotfiles watch install`).

Why the watcher does not auto-commit even though every other helper does:

- **No human authored the edit.** The commit-on-change rule exists to close the "I edited and forgot to commit" gap. A watcher-triggered absorb wasn't authored by anyone; it just mirrors what the system noticed. Auto-committing it would turn the commit log into a noise-stream of mechanical mirrors.
- **The review gate has to live somewhere.** With `dotfiles edit`, the human is at the keyboard and can see what's happening; auto-commit is fine. With the watcher, the human isn't watching — `git status` review before `git commit` is the only step where they can catch an accidental edit, secret leak, or scratch file.
- **Public repo.** A leaked secret committed by a daemon is harder to discover and revert than one committed by an interactive helper.

So the watcher absorbs to the working tree and stops. `dotfiles drift` and `dotfiles edit` continue to auto-commit by default; the watcher is the one exception, scoped to the new "absorb continuously, review before commit" use case introduced in S-64.
