---
id: S-48
title: Narrow `chezmoi apply` scope in `dotfiles secret add` / `secret rm`
type: fix
status: done
date: 2026-05-01
---

# S-48: Narrow `chezmoi apply` scope in `dotfiles secret add` / `secret rm`

## Problem

The current implementation of `dotfiles secret add` (and to a lesser extent
`secret rm`) runs a full-tree `chezmoi apply` after editing
`.chezmoidata/secrets.toml`. The intent is "render the new entry into
`~/.config/fish/conf.d/secrets.fish`," but the actual command applies
**every** managed file. Two failure modes follow:

1. **Unrelated drift can abort the apply mid-stream**, after `secrets.fish`
   has already been re-rendered. Observed during S-47 verification on
   2026-05-01: a `--force` re-registration of `OP_SERVICE_ACCOUNT_TOKEN`
   caused `chezmoi apply` to:
   1. Render and deploy `~/.config/fish/conf.d/secrets.fish` with the new line,
   2. Continue, hit unrelated drift on `~/.config/zed/settings.json`,
   3. Exit non-zero on the Zed TTY-prompt failure.

   The script's revert path then ran:
   ```fish
   chezmoi apply; or begin
       echo "✗ chezmoi apply failed; reverting registry"
       sed -i '' "/^$var = /d" $data
       return 1
   end
   ```
   Registry got reverted; deployed `secrets.fish` did not. Source and target
   silently drifted. Every new fish shell continued to load the unwanted
   variable.

2. **Interactive prompts on unrelated files block the secret op.** Anything
   that triggers `chezmoi`'s "file modified externally" prompt (Zed,
   permissions overlays, etc.) makes `dotfiles secret add` look like it
   failed even when the secret-related apply succeeded.

The user's mental model is "this command edits one file, and reflects it in
one other file." The implementation is "this command runs the entire apply
pipeline." Mismatch.

## Non-goals

- Reworking how `chezmoi apply` handles partial failures globally. Out of
  scope; this spec is targeted at the `dotfiles secret` subcommands only.
- Adding a "rollback target" mechanism to chezmoi itself.
- Changing the registry file format or the `secrets.fish.tmpl` rendering
  logic.

## Solution

Pass the specific target path(s) to `chezmoi apply` so only the file driven
by the registry change is touched. `chezmoi apply <path>` exists for exactly
this case; the broader tree is left alone.

### `secret add`

Replace:
```fish
echo "→ chezmoi apply"
chezmoi apply; or begin
    echo "✗ chezmoi apply failed; reverting registry"
    sed -i '' "/^$var = /d" $data
    return 1
end
```

With:
```fish
set -l target $HOME/.config/fish/conf.d/secrets.fish
echo "→ chezmoi apply $target"
chezmoi apply $target; or begin
    echo "✗ chezmoi apply failed; reverting registry"
    sed -i '' "/^$var = /d" $data
    return 1
end
```

If the narrow apply fails, the only target that could have been re-rendered
is `secrets.fish` itself; if it was, the registry revert + a second narrow
apply would put both source and target back in sync. To be belt-and-braces,
strengthen the revert branch:

```fish
chezmoi apply $target; or begin
    echo "✗ chezmoi apply failed; reverting"
    sed -i '' "/^$var = /d" $data
    chezmoi apply $target >/dev/null 2>&1   # re-render without the line
    return 1
end
```

### `secret rm`

Same change. `chezmoi apply` becomes `chezmoi apply $target`. The current
`rm` failure mode is benign (target file was already rendered without the
line — the desired state — so even on unrelated apply failure, removal is
effectively complete). But narrowing the scope still avoids confusing
"removal failed" messages caused by drift elsewhere.

### `secret refresh`

No change needed. `refresh` already operates only on the Keychain entry
and re-fetches via `secret-cache-read`; it doesn't run `chezmoi apply`.

## Files changed

**Modified:**
- `home/dot_config/fish/functions/dotfiles.fish`: narrow `chezmoi apply` to
  the secrets.fish target in both `secret add` and `secret rm` branches;
  add re-apply on revert in `secret add`.

**Not changed:**
- `home/dot_config/fish/conf.d/secrets.fish.tmpl`: unchanged.
- `home/.chezmoidata/secrets.toml`: unchanged.
- The chezmoi script-execution-order / `run_onchange_*` machinery: unchanged.

## Trade-offs accepted

| Trade-off | Rationale |
|---|---|
| Hardcodes the secrets.fish target path in two places | Acceptable; the registry → secrets.fish mapping is intrinsic to the design. If we ever fan out to multiple targets (e.g., secrets-as-shell-snippets in zsh too), revisit then. |
| Doesn't run other `chezmoi apply` side-effects (e.g. brew bundle hash check, run_onchange scripts) | Desired. `dotfiles secret add` should not surprise the user by triggering a brew run or a guardrails reinstall. |

## Testing

```fish
# 1. Reproduce the original bug, confirm it's fixed.
#    Pre-condition: have unrelated drift in ~/.config/zed/settings.json.
dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN \
    "op://Private/op-service-account-ops/credential" --force
# Expect: secrets.fish is the only file touched; if it fails, revert leaves
# both source AND target without the line. No half-state.

dotfiles secret rm OP_SERVICE_ACCOUNT_TOKEN

# 2. Confirm source/target stay in sync after a forced failure.
#    Mock failure scenario by deleting a chezmoi-managed support file
#    temporarily, retry secret add, verify revert leaves grep -c == 0 on
#    both secrets.toml and ~/.config/fish/conf.d/secrets.fish.

# 3. Lint.
fish -n home/dot_config/fish/functions/dotfiles.fish
```

## Out of scope (deferred)

- A general "transactional apply" wrapper for chezmoi. If this kind of
  source/target drift shows up in other `dotfiles` subcommands, factor it
  into a helper then.
- Telemetry on revert events. Not worth the surface area for a one-off
  edge case.
