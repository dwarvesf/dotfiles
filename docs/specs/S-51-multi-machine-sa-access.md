---
id: S-51
title: Multi-machine SA access (SSH-driven secondary fish login + remote keychain seed)
type: feature
status: done
date: 2026-05-07
extends: S-49
---

# S-51: Multi-machine SA access for SSH-driven secondary operation

## Variables used in this spec

This is a framework spec. It uses placeholder names; substitute when you apply
the pattern to your own setup. The author's specific application (with real
hostnames, vault paths, SSH aliases) lives in
[`docs/operations/2026-05-mini-sa-seed.md`](../operations/2026-05-mini-sa-seed.md).

| Placeholder | Meaning | Example |
|---|---|---|
| `$PRIMARY` | Daily-driver Mac with a continuous GUI session. The machine where biometric works and 1Password desktop runs. | A MacBook you carry. |
| `$SECONDARY` | Second daily-driver Mac, also a workstation, but operated mostly over SSH. The machine that needs SA token in env without biometric. | A Mac mini in your office. |
| `$SECONDARY_SSH_ALIAS` | The SSH config alias that resolves to `$SECONDARY` for the user account that owns the dotfiles. | `secondary-host` |
| `$SA_REF` | The `op://Vault/Item/field` reference to your service-account token's credential. | `op://YourVault/agent-token/credential` |

The mental model and gate flow are universal. Only the names change per setup.

## Problem

The dotfiles' [S-49](S-49-dual-mode-op-via-fish-interceptor.md) dual-mode
design works perfectly on a single machine with a GUI session ($PRIMARY): SA
token auto-loads at fish login, subprocess `op read` uses bearer auth,
interactive `op` uses biometric. $SECONDARY, used as a second daily driver
but operated mostly over SSH, breaks this model in two specific places.

### Symptom 1: token never lands in env over SSH

`secrets.fish` is gated on `if status is-interactive`. Three of the four
ways SSH delivers a fish session interact badly with this gate:

| SSH invocation | Gate result | Token loaded? |
|---|---|---|
| `ssh $SECONDARY_SSH_ALIAS` (TTY allocated, fish login shell, interactive) | passes | yes (if Keychain seeded) |
| `ssh $SECONDARY_SSH_ALIAS '<cmd>'` (no TTY, fish login shell, non-interactive) | **fails** | **no** |
| iOS Termius / Blink with TTY | passes | yes |
| iOS Termius / Blink running a one-shot command | **fails** | **no** |

Empirical verification example (run from $PRIMARY, before this spec lands):

```fish
ssh $SECONDARY_SSH_ALIAS -- /opt/homebrew/bin/fish -l -c \
    'string sub -l 4 "$OP_SERVICE_ACCOUNT_TOKEN"'
# (empty)
```

Anything that runs `ssh $SECONDARY_SSH_ALIAS '<cmd>'` to invoke an `op read`
(ops scripts, cron-like flows, agent-from-elsewhere calls) gets nothing.

### Symptom 2: Keychain entry not seeded on $SECONDARY

Even when Gate 1 passes, Gate 2 (Keychain hit) misses on $SECONDARY. The
seed flow expects "first interactive fish login on a new machine triggers
biometric to populate the Keychain." When that first login is over SSH,
biometric isn't available and `op read` falls through silently. The entry
never gets created.

### Together

Both gaps must close for SSH-driven `op read` on $SECONDARY to work.
Closing one without the other still fails: a working `is-login` gate hits a
missing Keychain entry, or a present Keychain entry never gets queried.

## Solution

Two minimal changes. Both stay inside the dotfiles surface.

### Change 1: relax Gate 1 from `is-interactive` to `is-login`

`home/dot_config/fish/conf.d/secrets.fish`:

```diff
-if status is-interactive
+if status is-login
```

`is-login` is true for:

- interactive login fish (existing daily case)
- non-interactive login fish from `ssh user@host '<cmd>'` (the new case
  we want to support)

It remains false for:

- `fish file.fish` script invocations (correct: scripts shouldn't trigger
  secret loads)
- subshells / `fish -c '...'` non-login invocations

This widens the secrets-load surface to cover SSH-driven flows. The other
guards (S-48 narrow apply, S-49 op interceptor) remain unchanged and still
do their jobs.

### Change 2: a `dotfiles secret push` helper to seed remote Keychain

A new sub-command in `home/dot_config/fish/functions/dotfiles.fish` that
seeds a remote machine's Keychain without requiring biometric on the remote.
Usage:

```fish
# from $PRIMARY (where biometric works)
dotfiles secret push <VAR_NAME> <$SECONDARY_SSH_ALIAS>
# reads op://... locally, pipes value over SSH, runs security add-generic-password on the remote
```

Invariants:

- Read on the local ($PRIMARY) side via `op read`, where biometric works.
  Internally, the helper drops `OP_SERVICE_ACCOUNT_TOKEN` from the env so
  `op read` always uses your full-vault biometric session, regardless of
  whether the helper was invoked from interactive or non-interactive fish.
  This is required because the SA cannot read its own credential ([S-46](S-46-three-vault-model-for-agent-infra-secrets.md)
  keeps `Private` outside SA scope by design).
- Pipe over SSH so the value never appears in any process listing or
  command-line history on the remote.
- The remote write uses `-A` (allow any application owned by the user) and
  `-U` (update if present). `-A` is required for cross-session reads to
  succeed; without it, macOS binds the item's ACL to the originating
  process context and SSH-context reads fail silently. `-U` makes the
  helper idempotent for token rotation.
- Read-back verification: the helper reads the Keychain entry's prefix
  back through SSH and compares to the value it sent. Surfaces both ACL
  and lock failures with actionable messages, instead of trusting SSH's
  exit-status propagation through `bash -c` under a fish login shell
  (which is unreliable).

### Change 3: `secret-cache-read` writes with `-A`

`home/dot_local/bin/executable_secret-cache-read` caches each loaded secret
in the Keychain after a successful `op read`. That cache write must also
use `-A` for the same reason: a cached entry without `-A` is invisible to
SSH-context reads, causing `secret-cache-read` to fall through to `op read`
on every SSH login and triggering a biometric popup that can't be answered
headlessly.

### Operational prerequisite (NOT a dotfiles change)

$SECONDARY's login keychain must be **unlocked** at the time `secret-cache-read`
queries it. SSH key-auth sessions do not unlock the login keychain; only a
GUI login does. The simplest persistent fix on a personal home machine is
to enable auto-login (System Settings → Users & Groups). The trade-off and
alternatives live in
[`docs/1password-multi-machine.md`](../1password-multi-machine.md). This
choice is operational, not codified in dotfiles.

## Trade-offs accepted

| Trade-off | Rationale |
|---|---|
| Secrets now load even in non-interactive SSH login shells | This is the entire point of S-51. The widening is intentional. Non-login subshells (`fish -c '...'` without `-l`) still don't load. |
| Token rotation requires re-running `dotfiles secret push` per remote | Acceptable; SA tokens rotate rarely. Could be automated later if rotation becomes frequent. |
| $SECONDARY's auto-login (or equivalent unlock) choice is operational, not codified | Different homes / offices have different threat models. The dotfiles repo describes the trade-off; the user picks. |
| Keychain-locked-after-reboot edge case persists | Not a dotfiles problem to solve; auto-login or post-reboot GUI login covers it. Documented. |
| iOS-driven `git push` from $SECONDARY still requires per-iOS-client SE keys | Out of scope. No clean fix from inside dotfiles. Documented as a future option. |
| `-A` ACL flag is broadly permissive | Same blast radius as the env-var model: any process the user runs can read. Necessary for cross-session reads. Documented. |

## Non-goals

- Solving outbound `git push` from $SECONDARY over iOS-originated SSH.
  (Needs an SE-bound SSH key in the iOS client, registered with GitHub.
  Per-user setup, not dotfiles-managed. See multi-machine doc for the
  recipe.)
- Implementing [S-46](S-46-three-vault-model-for-agent-infra-secrets.md)
  vault tiering. (Separate spec; orthogonal to S-51's delivery problem.)
- Replacing the [S-49](S-49-dual-mode-op-via-fish-interceptor.md)
  interceptor's behavior on $SECONDARY (where typed `op` over SSH falls
  through to biometric and fails). Workaround documented: `command op
  read ...` for bypass.
- Building a `dotfiles secret push --all` bulk seed. Premature; revisit
  if the registered-secret count grows past the current handful.
- Cron-based or scheduled re-seed. Manual is fine until proven otherwise.
- Encoding $SECONDARY's auto-login decision in dotfiles.

## Files changed

**New:**
- `docs/specs/S-51-multi-machine-sa-access.md` (this spec)
- `docs/1password-multi-machine.md` (companion architecture doc)

**Modified:**
- `home/dot_config/fish/conf.d/secrets.fish`: change `if status is-interactive`
  → `if status is-login`. Update the comment block to explain the new
  envelope.
- `home/dot_config/fish/functions/dotfiles.fish`: add the `secret push`
  sub-command alongside `add` / `rm` / `list` / `refresh`.
- `docs/1password.md`: add a "Multi-machine" subsection that points at
  `1password-multi-machine.md`. One paragraph, no duplication.
- `docs/tasks.md`: add S-51 entry.
- `docs/sync-log.md`: hostname-tagged entry on first apply per machine.
- `README.md`: tiny addendum to the dual-mode summary referencing the
  multi-machine doc.

**Modified by amendment commits on this PR:**
- `home/dot_local/bin/executable_secret-cache-read`: cache write now uses
  `-A` to allow cross-session reads of cached secrets. Without `-A`, a
  cached entry written from a GUI session is invisible to SSH-context
  reads, breaking S-51's whole point.

**Not changed:**
- `home/dot_config/fish/functions/op.fish`: unchanged. The S-49 interceptor
  still does the right thing on $PRIMARY. On $SECONDARY, typed `op` over
  SSH falls through to biometric and fails, but the workaround
  (`command op`) is fine and the failure mode is loud (empty output),
  not silent corruption.
- `home/.chezmoidata/secrets.toml`: unchanged. SA registration entries
  are unaffected.

## Framework discipline

This spec is a **forkable pattern**, not a personal cookbook. Anyone
running this dotfiles framework on a similar machine pair (one GUI-driven,
one SSH-driven) should be able to apply the pattern without reading any
of the author's specifics.

The contract that enforces this:

| Doc class | Path | Allowed personal context |
|---|---|---|
| Framework spec (this file) | `docs/specs/` | None. Use placeholders ($PRIMARY, $SECONDARY, $SECONDARY_SSH_ALIAS, $SA_REF). |
| Framework architecture | `docs/1password-multi-machine.md` | None. Same rule. |
| Author's application | `docs/operations/2026-05-mini-sa-seed.md` | All. Hostnames, vault paths, SSH aliases, PR refs. Dated and explicitly the author's record. |

A grep contract verifies the rule (see Testing → "Doc verification").

## Testing

Three layers: doc verification (the framework discipline), $PRIMARY-side
regression, end-to-end on $SECONDARY.

### Doc verification (framework discipline)

The doc-discipline contract is enforced by a runnable test script at
`scripts/test-doc-discipline.sh`. The script encodes the rule from the
**Framework discipline** section above: framework docs must be placeholder-
clean; operations cookbooks must contain author specifics. The script's
source assembles its match patterns from string parts so the script itself
doesn't contain the matchable substrings verbatim (avoids self-match).

```fish
# from the repo root
./scripts/test-doc-discipline.sh             # quiet, exits 0 on pass
./scripts/test-doc-discipline.sh --verbose   # prints leaked lines on fail

# expected output on pass:
#   [1/2] Framework docs (must be placeholder-clean):
#     ✓ docs/specs/S-51-multi-machine-sa-access.md
#     ✓ docs/1password-multi-machine.md
#   [2/2] Operations cookbooks (must contain author's specifics):
#     ✓ docs/operations/2026-05-mini-sa-seed.md (contains author's specifics, as expected)
#   ✓ Doc discipline contract holds.
```

This test should also run in CI so personal context can't slip back into
framework docs unnoticed.

### $PRIMARY-side regression (fast)

```fish
# 1. Interactive login fish loads token.
exec fish
echo $OP_SERVICE_ACCOUNT_TOKEN | head -c 4   # expect: ops_

# 2. Interactive op uses biometric (full vault list, requires real TTY).
op vault list | tail -n +2 | wc -l           # expect: > 1

# 3. Subprocess op uses bearer (SA scope).
bash -c 'op vault list | tail -n +2 | wc -l' # expect: 1

# 4. New helper exists.
dotfiles secret push 2>&1 | head -1          # expect: usage line

# 5. Non-interactive login fish ALSO loads token (the S-51 win).
fish -l -c 'string sub -l 4 -- "$OP_SERVICE_ACCOUNT_TOKEN"'  # expect: ops_
```

### End-to-end ($SECONDARY-side)

```fish
# 6. Push the SA token to $SECONDARY.
dotfiles secret push <VAR_NAME> $SECONDARY_SSH_ALIAS
#    expect: "✓ Seeded <VAR_NAME> on $SECONDARY_SSH_ALIAS. (verified by read-back)"

# 7. Confirm Keychain entry readable from SSH context.
ssh $SECONDARY_SSH_ALIAS 'security find-generic-password -a "$USER" -s <VAR_NAME> -w | head -c 4'
#    expect: ops_  (or whatever the value's prefix is)

# 8. Apply dotfiles to $SECONDARY so secrets.fish gets the is-login change.
ssh $SECONDARY_SSH_ALIAS 'chezmoi apply ~/.config/fish/conf.d/secrets.fish'

# 9. SSH login shell on $SECONDARY loads the token.
ssh $SECONDARY_SSH_ALIAS -- fish -l -c 'string sub -l 4 -- "$OP_SERVICE_ACCOUNT_TOKEN"'
#    expect: ops_

# 10. Subprocess `op read` over SSH works headlessly, no popup on $SECONDARY.
ssh $SECONDARY_SSH_ALIAS -- fish -l -c 'bash -c "op whoami | grep \"User Type:\""'
#    expect: User Type:  SERVICE_ACCOUNT

# 11. Non-regression: typed op over SSH still fails (S-49 interceptor unchanged).
#     Documented behavior; workaround is `command op read ...`.
ssh -t $SECONDARY_SSH_ALIAS -- fish -l -i -c 'op whoami' 2>&1 \
    | grep -qE 'biometric|error|not signed in'
#    expect: matches (i.e. NOT a SERVICE_ACCOUNT result)
```

Test 11 is a **non-regression** check: it should continue to fail the same
way after S-51 ships, confirming we haven't accidentally broken the S-49
interceptor.

### Edge case: $SECONDARY post-reboot

After $SECONDARY cold-boots without a GUI login, the login keychain is
locked. SSH-context reads return empty, and `op read` fallback triggers
biometric that can't be answered. Expected and documented; not a dotfiles
bug. Mitigation lives in `docs/1password-multi-machine.md`. Test:

```fish
# Reproduce the failure mode (confirms the documented behavior holds):
ssh $SECONDARY_SSH_ALIAS -- fish -l -c 'string sub -l 4 -- "$OP_SERVICE_ACCOUNT_TOKEN"'
#    expect: empty (Keychain locked, fall-through fails silently over SSH)
```

## Spec chain

| Spec | What | Status |
|---|---|---|
| [S-35](S-35-local-pattern-and-lazy-secrets.md) | Lazy resolution + Keychain cache | done |
| [S-42](S-42-service-account-agent-auth.md) | Service-account auto-load for agents | superseded by S-47, restored by S-49 |
| [S-46](S-46-three-vault-model-for-agent-infra-secrets.md) | Vault tiering | proposed |
| [S-47](S-47-agent-token-opt-in-wrapper.md) | Opt-in wrapper | amended by S-49 |
| [S-49](S-49-dual-mode-op-via-fish-interceptor.md) | Dual-mode `op` interceptor | done |
| **S-51** | **Multi-machine extension** | **proposed (this spec)** |

S-46 is independent of S-51 and can land before, after, or never. The
multi-machine extension does not depend on broadening the SA's vault scope.
