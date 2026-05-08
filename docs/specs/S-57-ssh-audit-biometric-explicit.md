---
id: S-57
title: `dotfiles ssh audit` strips SA token explicitly so it always runs biometric
type: fix
status: done
date: 2026-05-08
---

# S-57: `dotfiles ssh audit` always runs biometric

## Problem

`dotfiles ssh audit` calls `op item list --vault Private --categories
"SSH Key"` to inventory 1Password-backed SSH keys. The result on
Mac mini today (post-S-49 dual-mode op):

```
[3] SSH keys in 1Password (vault: Private)
-----------------------------------------------------------
  (no SSH Key items in vault)

[4] Backup status
  ⚠ 1 of 2 disk key(s) have no 1P backup
```

But running `op` directly with the token stripped finds 3 keys:

```
$ env -u OP_SERVICE_ACCOUNT_TOKEN op item list \
    --categories "SSH Key" --vault Private --format json | jq -r '.[].title'
id_rsa
id_ed25519_trading_vps
GitHub
```

The audit misleads the user into thinking adoption failed and prompts
them to re-run `dotfiles ssh adopt`, which silently no-ops because the
key is already adopted.

### Root cause

The S-49 dual-mode op interceptor (`home/dot_config/fish/functions/op.fish`):

```fish
function op --description 'op CLI: biometric in interactive shells, SA bearer auth in subprocesses (S-49)'
    if status is-interactive
        env -u OP_SERVICE_ACCOUNT_TOKEN command op $argv
    else
        command op $argv
    end
end
```

The interceptor strips the SA token only when `status is-interactive` is
true. Inside a script context (`fish -c 'dotfiles ssh audit'`,
`fish -l -c '...'`, `dotfiles ssh audit` invoked from a cron, CI, or
Claude Code's Bash tool), `status is-interactive` is **false**. The
interceptor passes through with SA bearer auth.

The user's SA token has access to `Toolkit` and `Trading` vaults (per
S-46/S-49) but **not** `Private`. So `op item list --vault Private`
returns:

```
[ERROR] "Private" isn't a vault in this account.
```

The audit eats that error with `2>/dev/null`, sees an empty `items_json`,
and reports "(no SSH Key items in vault)".

The audit's intent is "show what's in 1P from the user's full-vault
perspective." That's a biometric concern, not an SA-bearer-auth concern.
The current code conflates the two by relying on the interceptor's
context-sensitive behavior.

## Solution

Strip the SA token explicitly inside the audit case, regardless of
interactive status. Replace the four `op` calls in the audit with the
biometric-explicit form `env -u OP_SERVICE_ACCOUNT_TOKEN command op ...`.

The relevant calls in `home/dot_config/fish/functions/dotfiles.fish`
within `case audit`:

```diff
-                    else if not op account get >/dev/null 2>&1
+                    else if not env -u OP_SERVICE_ACCOUNT_TOKEN command op account get >/dev/null 2>&1
                         echo "  (not signed in to 1Password; run: op signin)"
                     else
-                        set -l items_json (op item list --categories "SSH Key" --vault $vault_default --format json 2>/dev/null)
+                        set -l items_json (env -u OP_SERVICE_ACCOUNT_TOKEN command op item list --categories "SSH Key" --vault $vault_default --format json 2>/dev/null)
                         ...
                             for id in (echo $items_json | jq -r '.[].id' 2>/dev/null)
                                 ...
-                                set -l pubkey (op item get $id --fields label="public key" --reveal 2>/dev/null)
+                                set -l pubkey (env -u OP_SERVICE_ACCOUNT_TOKEN command op item get $id --fields label="public key" --reveal 2>/dev/null)
```

The pattern matches what `dotfiles-sync` already does for its own
notify-only checks (`env -u OP_SERVICE_ACCOUNT_TOKEN op account get`).
The same fix applies to other `dotfiles ssh` subcommands that need the
user's full-vault view (likely `adopt` already does this implicitly via
the `--vault Private` requiring biometric).

### Related: `dotfiles ssh adopt` and other subcommands

A full audit of the `case audit / adopt / backup / list` blocks reveals
the same pattern: any code path that needs to read user-owned 1P items
needs to be biometric-explicit. Per spec scope, S-57 fixes the audit
case end-to-end and **leaves adopt/backup/list to a follow-up if symptoms
surface**. The audit is the user-visible nag; adopt already works
because users invoke it interactively.

## Test

1. **Reproduce.** From a non-interactive context, `dotfiles ssh audit`
   reports `(no SSH Key items in vault)` even when keys exist in
   Private. Direct `env -u OP_SERVICE_ACCOUNT_TOKEN op item list ...`
   finds them.
2. **Fix verification.** After patch, `fish -l -c 'dotfiles ssh audit'`
   reports the 3 SSH keys in Private (id_rsa, id_ed25519_trading_vps,
   GitHub) with their fingerprints. `[4] Backup status` reports
   `✓ all 2 disk key(s) have a 1P counterpart` (or accurately reflects
   any unbacked).
3. **Interactive parity.** `fish -l -i -c 'dotfiles ssh audit'` produces
   identical output to `fish -l -c '...'`. Behavior no longer depends
   on caller context.
4. **Subprocess invocation (this skill's use case).** Calling
   `dotfiles ssh audit` from Claude Code's Bash tool (non-interactive,
   SA token loaded) produces the correct full-vault output.
5. **Regression.** S-49 dual-mode behavior is preserved for everything
   *outside* the audit case: `op read op://...` from a subprocess still
   uses SA bearer auth (the audit fix is local to the audit case;
   nothing else changes).

## Out of scope

- **Restoring the SA token after the audit's `op` calls.** Each call is
  scoped via `env -u`; nothing outside the audit case is affected.
- **Adding a fish helper** `__dotfiles_op_biometric` for reuse. The
  pattern is short and explicit; introducing a helper is premature
  abstraction unless 3+ call sites need it. Revisit if that count grows.
- **Fixing `dotfiles ssh adopt`** to be biometric-explicit. It works in
  the user's interactive shell today, which is where `adopt` is meant
  to be invoked. If a CI / unattended use case surfaces, file a
  follow-up.
- **Restoring the audit's "(not signed in)" hint accuracy** when the
  user's biometric session is stale. The hint already says "run:
  op signin" which is correct.

## Definition of done (per S-44)

- [x] Spec frontmatter `status: done`
- [x] Tick in `docs/tasks.md`
- [x] Hostname-tagged entry in `docs/sync-log.md`
- [x] Test 2 + Test 3 pass on Mac mini (3 keys reported, parity across
      interactive/non-interactive)
