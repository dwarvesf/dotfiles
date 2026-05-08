---
id: S-47
title: Opt-in `OP_SERVICE_ACCOUNT_TOKEN` via per-launch wrapper
type: feature
status: amended by S-49
date: 2026-05-01
supersedes: S-42
---

> **Amended by [S-49](S-49-dual-mode-op-via-fish-interceptor.md) (same day,
> 2026-05-01).** S-47 fixed the daily-shell scoping problem by removing the
> token from auto-load and exposing a `with-agent-token` wrapper. That
> traded away the headless-`op read` capability for default `claude`
> sessions. S-49 keeps S-47's daily UX *and* restores the headless agent
> capability by auto-loading the token AND intercepting `op` in interactive
> fish. The wrapper still ships and is functional; it's just no longer the
> primary path. The `dotfiles secret add` guard introduced here was removed
> in S-49.

# S-47: Opt-in `OP_SERVICE_ACCOUNT_TOKEN` via per-launch wrapper

## Problem

[S-42](S-42-service-account-agent-auth.md) registered `OP_SERVICE_ACCOUNT_TOKEN`
in `.chezmoidata/secrets.toml` so that `secrets.fish.tmpl` exports it into
**every** interactive fish shell. That preserves headless `op read` capability
for any subprocess launched from any shell, but it has a cost S-42 did not
weigh: once the token is in env, the user's daily `op` CLI also switches to
bearer auth and is locked to whatever vaults the service account is scoped to.

Observed on this laptop on 2026-05-01:

```
$ op whoami
User Type:    SERVICE_ACCOUNT          # not USER_OF_ACCOUNT

$ op vault list
ID                            NAME
lvhnorvvwhnp6sjyzzcthdqmya    Trading  # all other vaults invisible
```

The user wants full multi-vault access in their daily shell. They keep losing
it because every fish login re-exports the token.

S-42 itself was correct: the token *is* needed for non-TTY `op read` from
agent subprocesses. The mistake was making it always-on instead of
opt-in-per-launch.

## Non-goals

- Removing service-account capability. The capability is still required for
  agents that need ad-hoc `op read` mid-session.
- Generalising to multiple service accounts. Defer until a second SA exists
  (S-46 may motivate this; revisit then).
- Storing the SA `op://` ref outside the wrapper function. One hardcoded ref
  in fish is fine for v1.
- Auto-detecting "this is an agent context" and injecting transparently. The
  user opts in explicitly per launch.

## Solution

### Two-tier launch model

| Launch | What's in env | Daily `op` CLI | Bash-tool `op read` |
|---|---|---|---|
| `claude` (default) | Pre-registered secrets only (`CLOUDFLARE_API_TOKEN`, `R2_*`, etc.) | Full biometric, all vaults | Fails silently (no TTY, no token) — same as pre-S-42 |
| `with-agent-token claude` | Pre-registered + `OP_SERVICE_ACCOUNT_TOKEN` | Service-account scope only inside the wrapped process | Works headlessly, scoped to SA vaults |

Default sessions lose the ad-hoc `op read` capability that S-42 added. That's
acceptable because:

1. Almost all secret access in this repo is via env vars resolved at shell
   startup (S-35 path), which `claude` already inherits.
2. The user's stated daily UX (multi-vault biometric `op` access) is
   incompatible with always-on token export.
3. Sessions that genuinely need ad-hoc `op read` opt in by prefixing the
   launch.

### `with-agent-token` wrapper

New file: `home/dot_config/fish/functions/with-agent-token.fish`

```fish
function with-agent-token --description 'Run cmd with OP_SERVICE_ACCOUNT_TOKEN injected'
    # Update this ref if the service-account 1P item changes.
    set -l ref "op://Private/op-service-account-ops/credential"
    set -l token ($HOME/.local/bin/secret-cache-read OP_SERVICE_ACCOUNT_TOKEN $ref)
    if test -z "$token"
        echo "with-agent-token: could not fetch $ref (op signed in?)" >&2
        return 1
    end
    OP_SERVICE_ACCOUNT_TOKEN=$token $argv
end
```

Reuses `secret-cache-read` so the wrapper is silent and fast after first
invocation (Keychain cache). `dotfiles secret refresh OP_SERVICE_ACCOUNT_TOKEN`
still works because that helper keys on the var name, not on whether the
secret is auto-exported.

### Guard against re-registering

`dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN ...` is now a footgun: it would
restore the always-on behaviour and undo S-47. Add a guard in
`home/dot_config/fish/functions/dotfiles.fish` (in the `secret add` branch,
after the var-name validation):

```fish
if test "$var" = OP_SERVICE_ACCOUNT_TOKEN; and not contains -- --force $argv
    echo "✗ refusing to register OP_SERVICE_ACCOUNT_TOKEN (S-47)"
    echo ""
    echo "  Auto-loading this var into every shell scopes the user's daily"
    echo "  op CLI to the service account. Use the wrapper instead:"
    echo ""
    echo "    with-agent-token claude         # opt in per launch"
    echo ""
    echo "  Override (not recommended): add --force"
    return 1
end
```

The wrapper itself fetches via `secret-cache-read`, so the Keychain entry
under the same var name stays valid; nothing about the cache layer changes.

### Anti-regression for future Claude Code sessions

A future Claude Code reading the repo would otherwise notice
`OP_SERVICE_ACCOUNT_TOKEN` is missing from `secrets.toml` and "fix" it by
re-registering. Three layers of defence:

1. **CLAUDE.md (project root) bullet on secret injection** — rewritten to
   describe the wrapper-based model and explicitly warn against
   `dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN`.
2. **`docs/guide.md` "Service account for agent subprocess `op read`"
   section** — rewritten to centre on `with-agent-token`, not auto-load.
3. **Runtime guard in `dotfiles secret add`** — even if the docs are missed,
   the command refuses without `--force`.

S-42 stays in place as historical record with `status: superseded by S-47`
in its frontmatter.

## Files changed

**New:**
- `docs/specs/S-47-agent-token-opt-in-wrapper.md` (this spec)
- `home/dot_config/fish/functions/with-agent-token.fish`

**Modified:**
- `home/.chezmoidata/secrets.toml`: remove `OP_SERVICE_ACCOUNT_TOKEN` line
- `home/dot_config/fish/functions/dotfiles.fish`: guard in `secret add`
- `CLAUDE.md`: rewrite the "Service account token" bullet (≈ lines 64–69)
- `docs/guide.md`: rewrite the "Service account for agent subprocess
  `op read`" section (≈ lines 746–793)
- `docs/specs/S-42-service-account-agent-auth.md`: frontmatter
  `status: superseded by S-47`
- `docs/tasks.md`: add S-47 entry
- `docs/sync-log.md`: hostname-tagged entry recording the change

**Not changed (intentionally):**
- `home/dot_local/bin/executable_secret-cache-read`: the wrapper reuses it
  unchanged
- `home/dot_config/fish/conf.d/secrets.fish.tmpl`: still iterates `.secrets`,
  but `OP_SERVICE_ACCOUNT_TOKEN` is no longer in that map

## Trade-offs accepted

| Trade-off | Rationale |
|---|---|
| Default `claude` sessions cannot do ad-hoc `op read` | Daily UX (multi-vault biometric) > undocumented agent capability. Sessions that need it opt in. |
| Wrapper hardcodes the SA `op://` ref | One SA today; generalising is YAGNI. Comment in the function notes where to update. |
| User must remember to prefix `with-agent-token` | The trade-off is explicit at launch time, which is the right surface. |

## Testing

```fish
# 1. Unregister + apply.
dotfiles secret rm OP_SERVICE_ACCOUNT_TOKEN
chezmoi apply
exec fish

# 2. Daily shell: full biometric access restored.
test -z "$OP_SERVICE_ACCOUNT_TOKEN"; and echo "PASS: token not in env"
op whoami | grep -q "User Type:.*USER_OF_ACCOUNT"; and echo "PASS: biometric session"
op vault list   # expect: more than just Trading

# 3. Wrapper: scoped headless access works.
with-agent-token op whoami | grep -q "SERVICE_ACCOUNT"; and echo "PASS: SA via wrapper"
with-agent-token op vault list   # expect: only Trading

# 4. Guard fires.
dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN "op://Private/x/y" 2>&1 | grep -q "with-agent-token"
    and echo "PASS: guard fires"

# 5. Lint.
fish -n home/dot_config/fish/functions/with-agent-token.fish
fish -n home/dot_config/fish/functions/dotfiles.fish
chezmoi apply --dry-run 2>&1 | tail -10
```

All five must pass before this spec moves to `status: done`.
