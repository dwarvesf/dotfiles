# 2026-05-10 SA rotation across Air + Mini (S-63 trigger event)

Author's specific record of the 1Password Service-Account rotation that
triggered the [S-63 spec](../specs/S-63-secret-rotate-multi-host.md).
This file is a **personal cookbook**, not a framework doc; real
hostnames (`mini-tieubao`), real `op://` references
(`op://Private/op-service-account-ops/credential`), and real
Integration IDs are intentional. Doc-discipline test verifies this
file contains personal markers (and that S-63 + the helper do not).

## Context

The SA backing `OP_SERVICE_ACCOUNT_TOKEN` was deleted upstream and a new
SA minted (the typical "rotation" pattern in 1Password's web admin —
delete + recreate with the same item path). Symptoms across Han's
machines:

- `op whoami` on Air returned `(403) Forbidden (Service Account
  Deleted)` because Air's shell env loaded the dead token from its
  own System.keychain at login time.
- `op whoami` via `env -u SSH_AUTH_SOCK ssh -a mini-tieubao
  '/opt/homebrew/bin/op whoami'` returned `account is not signed in`
  because the Mini's System.keychain entry held the stale token.
- Hermes daemon (`foundation.d.hermes-agent` on the Mini, running as
  the `server` user) was unaffected because it loads from a literal
  `.env` (`/Users/server/.hermes/.env`) populated via a manual `op
  inject` cycle, not via shell env. Last refresh was 2026-05-09; values
  in that file did not rotate.

## Pre-S-63 manual flow (the paste-job)

This is what got executed today, in three steps. Recording for
historical accuracy and because the pain motivated S-63.

### Step 1 — Mini System.keychain re-seed (delete-then-add via passwordless sudo)

```fish
# delete the stale entry (idempotent)
ssh mini-tieubao 'bash -c "sudo security delete-generic-password -a tieubao -s OP_SERVICE_ACCOUNT_TOKEN /Library/Keychains/System.keychain 2>&1 | tail -3"'

# read new SA token from Air biometrically, pipe to Mini, plant under sudo
env -u OP_SERVICE_ACCOUNT_TOKEN op read 'op://Private/op-service-account-ops/credential' \
  | ssh mini-tieubao 'bash -c "sudo security add-generic-password -a tieubao -s OP_SERVICE_ACCOUNT_TOKEN -w \"\$(cat)\" -A -T /usr/bin/security -T /opt/homebrew/bin/op /Library/Keychains/System.keychain"'  # secret-guard: allow ssh-stdin is safe consumer

# verify
env -u SSH_AUTH_SOCK ssh -a mini-tieubao '/opt/homebrew/bin/op whoami'
# expected: URL/Integration ID/User Type: SERVICE_ACCOUNT — actual: WEFFUGYW7FAMVKSSCV2RC7BQC4
```

**First attempt used `-A -U` instead of delete-then-add** and got bitten
by the ACL gate:

```
security: SecKeychainItemSetAccess: User interaction is not allowed.
security: SecKeychainItemCreateFromContent (/Library/Keychains/System.keychain):
          The specified item already exists in the keychain.
```

Exit code was 0 but neither the value nor the ACL changed. The fix
landed in retry as delete-then-add. **This gotcha is the load-bearing
discovery driving S-63 § Decision 2.**

### Step 2 — Air System.keychain re-seed (paste-by-user)

Same pattern, but local. Sudo prompted for password (Air's daily-driver
account; no NOPASSWD grant for `tieubao`):

```fish
sudo security delete-generic-password -a tieubao -s OP_SERVICE_ACCOUNT_TOKEN /Library/Keychains/System.keychain

env -u OP_SERVICE_ACCOUNT_TOKEN op read 'op://Private/op-service-account-ops/credential' \
  | sudo bash -c 'security add-generic-password -a tieubao -s OP_SERVICE_ACCOUNT_TOKEN -w "$(cat)" -A -T /usr/bin/security -T /opt/homebrew/bin/op /Library/Keychains/System.keychain'

sudo security find-generic-password -a tieubao -s OP_SERVICE_ACCOUNT_TOKEN -w /Library/Keychains/System.keychain | head -c 4
# expected: ops_
```

### Step 3 — Re-enable Mini `secrets.fish` (separate cleanup)

The Mini's `~/.config/fish/conf.d/secrets.fish` had been disabled
earlier this week (renamed `.disabled`) because a prior SA-deletion
incident bricked iPhone-mosh logins (memory: `feedback_op_sa_deletion_bricks_fish.md`,
`feedback_s53_rotation_delete_then_add.md`). Refined model
post-incident: the brick requires the keychain entry to be **missing
or empty**, not just stale. With Step 1 above seeding a valid token,
re-enabling is safe for steady-state operation.

```fish
ssh mini-tieubao 'bash -c "
  # clear any stale negative-cache markers
  mv \${XDG_CACHE_HOME:-\$HOME/.cache}/secret-cache-read/ \\
     \${XDG_CACHE_HOME:-\$HOME/.cache}/secret-cache-read.bak.before-reenable.\$(date +%Y%m%d-%H%M%S) 2>/dev/null

  # re-enable
  mv ~/.config/fish/conf.d/secrets.fish.disabled ~/.config/fish/conf.d/secrets.fish
"'
```

Verification:

```fish
env -u SSH_AUTH_SOCK ssh -a mini-tieubao '/opt/homebrew/bin/op whoami'
# Integration ID: WEFFUGYW7FAMVKSSCV2RC7BQC4 ✓

ssh mini-tieubao 'fish -l -c "set -q OP_SERVICE_ACCOUNT_TOKEN; and echo OP_set; set -q CLOUDFLARE_API_TOKEN; and echo CF_set; set -q R2_ACCESS_KEY_ID; and echo R2k_set; set -q R2_SECRET_ACCESS_KEY; and echo R2s_set"'
# expected: 4 _set lines — actual: all 4 ✓
```

## Post-S-63 equivalent (one-liner)

What the same rotation will look like once S-63 is the deployed `push`
surface (Han's setup; substitute placeholders for your own):

```fish
# from $PRIMARY (Air)
dotfiles secret push OP_SERVICE_ACCOUNT_TOKEN mini-tieubao --local --backing-store=system
```

Output (modeled):

```
✓ local (OP_SERVICE_ACCOUNT_TOKEN seeded, verified by read-back)
✓ mini-tieubao (OP_SERVICE_ACCOUNT_TOKEN seeded, verified by read-back)
---
Summary: 2 succeeded, 0 failed (of 2 targets, backing=system)
```

Differences from the manual paste-job:

| Pre-S-63 | Post-S-63 |
|---|---|
| 6 commands across 3 sessions | 1 command, one session |
| Manually remembered delete-then-add per host | Helper does it unconditionally; can't forget |
| Neg-cache cleanup not done (left for next cron sweep) | Neg-cache cleared per-target as side effect |
| First attempt used `-U`, silently failed, had to retry | Helper ignores the `-U` path entirely |
| Verify required separate `op whoami` invocation per host | Verify by read-back is the success contract |

## Secret-guard interactions encountered

The S-62 secret-guard PreToolUse hook flagged several legitimate
patterns during today's manual flow. Recording for the next operator:

- `op read 'op://...' | ssh host 'sudo bash -c "..."'` triggers
  rule B1 ("1Password CLI output would land in the transcript")
  because the hook can't reason that `ssh` with stdin is a safe
  consumer. Bypass: append `# secret-guard: allow ssh-stdin is safe
  consumer; token never echoed locally`. Documented in S-63 § Decision 9.
- `cat /Users/tieubao/.local/bin/secret-cache-read` (reading the
  source, not invoking) triggers rule B2 because the hook matches the
  command name. Bypass: `# secret-guard: allow reading source code,
  not invoking`.
- `string length -- $OP_SERVICE_ACCOUNT_TOKEN` (presence-only check)
  triggers rule B3 even though only a length is printed. Workaround:
  use `set -q OP_SERVICE_ACCOUNT_TOKEN` + branch on exit code.

These are not bugs in the hook; they're conservative-by-default
matches. Document the bypass marker per use site so the audit log
records intent.

## Things deliberately out of scope for this event

- **Loader TTY-guard hardening** (`[ -t 0 ]` check in `secret-cache-read`
  step 3 to skip the `op read` fallback in non-TTY contexts). Real
  fix for the iPhone-mosh brick failure mode, but not part of the
  rotation. Tracked as a separate dotfiles follow-up; not in S-63.
- **Hermes `.env` audit**. Hermes uses its own literal `.env` populated
  via manual `op inject`. Today's rotation didn't touch Hermes; if
  any of the values inside Hermes's `.env` are also SA-derived (CF,
  R2, etc.) and got rotated server-side, Hermes would silently use
  stale values. Out of scope for the SA-token rotation event itself.
- **Other hosts** (`trading-egress-tokyo`, `egress`). Linux, different
  secret-loading model; System.keychain doesn't apply. Audit
  separately if/when those hosts join the dotfiles fleet.

## Cross-references

- Spec: [S-63](../specs/S-63-secret-rotate-multi-host.md)
- Predecessor event: [2026-05 mini SA seed](2026-05-mini-sa-seed.md)
  (S-51 first-seed; superseded for SSH/mosh path by S-53)
- Architecture: [secrets-architecture.md](../secrets-architecture.md)
- Personal memory notes (private, not in repo):
  `feedback_s53_rotation_delete_then_add.md`,
  `feedback_op_sa_deletion_bricks_fish.md` (refined model post-event).
