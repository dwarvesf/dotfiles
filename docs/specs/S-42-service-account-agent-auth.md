---
id: S-42
title: 1Password service account token for agent subprocess auth
type: feature
status: superseded by S-47
date: 2026-04-23
---

> **Superseded.** Chain: [S-42] → [S-47](S-47-agent-token-opt-in-wrapper.md) (2026-05-01)
> → [S-49](S-49-dual-mode-op-via-fish-interceptor.md) (2026-05-01, current).
> S-47 swapped auto-load for an opt-in `with-agent-token` wrapper to fix the
> daily-shell scoping problem this spec created. S-49 then restored auto-load
> AND added a fish `op` interceptor that strips the token inline for
> interactive calls -- the current production model. Read S-49 for the
> active design; this spec is historical record. **For an explainer that
> ties all three together, see [docs/1password.md](../1password.md).**

# S-42: 1Password service account token for agent subprocess auth

## Problem

Claude Code (and any other LLM agent running as a fish subprocess) needs to
read secrets from 1Password mid-session, e.g. `op read op://Toolkit/binance/api_key`
inside a tool call. Our existing S-35 design handles this cleanly for
**pre-registered** secrets: they're resolved once at shell login via
`secret-cache-read` and inherited as env vars. But ad-hoc `op read` calls from
a subprocess hit a dead end:

```
claude (parent shell)
  └─ Bash tool invokes: op read op://...
      └─ op sees stdin is not a TTY
      └─ refuses to trigger biometric popup
      └─ exit 1 (silent)
```

`op` deliberately does not prompt for biometric when it cannot detect an
interactive session. Our `secret-cache-read` only works because the user ran
it from a real fish login first, warming the Keychain. For secrets the agent
needs but we didn't pre-register, the session is stuck.

Two workarounds existed before this spec; both have issues:

1. **`eval (op signin)` before launching Claude.** Creates `OP_SESSION_*`
   env vars that expire after 30 min idle and die on shell exit. Every shell
   re-auth requires biometric. Not resilient for long-running agent sessions.
2. **Pre-register every secret the agent might want.** Defeats the point of
   having a secrets manager; only works for fully predictable workloads.

## Non-goals

- Replacing `secret-cache-read` or `onepasswordRead` for secrets we already
  register by name. Both continue to work for their original use cases.
- Automated token rotation. Rotation remains a manual web-console action
  followed by `dotfiles secret refresh`.
- Support on 1Password Individual/Family plans. Service accounts require
  Business or Teams. This spec assumes the user's plan supports them; fallback
  is the existing per-secret registration path.
- Multi-user / shared-machine isolation. The token is treated as a single
  user's credential; the Keychain entry is per-login-account.

## Solution

Use a 1Password **service account token** as the non-interactive auth
mechanism for subprocess `op read` calls. The token itself is stored in
1Password like any other secret and loaded into the shell env via the
existing `secret-cache-read` infrastructure. Once `OP_SERVICE_ACCOUNT_TOKEN`
is in env, any child process that calls `op` skips biometric entirely and
uses bearer auth.

### Flow

```
fish login (interactive)
  └─ secrets.fish.tmpl loops .chezmoidata/secrets.toml
      └─ OP_SERVICE_ACCOUNT_TOKEN entry
          └─ secret-cache-read VAR OP_REF
              ├─ Keychain hit (subsequent shells) → silent
              └─ Keychain miss (first shell on new machine)
                  └─ op read OP_REF → biometric popup (once) → cache in Keychain
          └─ export OP_SERVICE_ACCOUNT_TOKEN into fish env
  └─ user launches `claude`
      └─ claude inherits OP_SERVICE_ACCOUNT_TOKEN
          └─ any `op read op://...` inside an agent tool call
              └─ op sees OP_SERVICE_ACCOUNT_TOKEN set → bearer auth
              └─ reads secret silently (no popup, no session timeout)
```

### Zero new code

The existing `dotfiles secret add` tooling, `.chezmoidata/secrets.toml`
loop in `secrets.fish.tmpl`, and `secret-cache-read` helper all work without
modification. The service account token is a registered secret with a
reserved name that `op` itself recognises.

### Required setup (per user, one-time)

1. Create a 1Password service account in the web admin console, scoped to
   the vaults the agent needs to read (recommended: a dedicated `Agents`
   vault, not the user's `Private` vault).
2. Store the resulting `ops_...` token as a regular 1Password item, e.g.
   `op://Private/op-service-account-<purpose>/credential`.
3. On each machine:
   ```fish
   dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN "op://Private/op-service-account-<purpose>/credential"
   exec fish
   ```

That's it. From now on, every fish login on that machine loads the token,
and every agent run inherits it.

## Architecture decisions recorded

1. **Reuse existing infrastructure.** A service account token is just a
   string; treating it like any other registered secret means zero new code
   paths, zero new abstractions, and zero new failure modes beyond what S-35
   already introduced.
2. **Token in 1P, not in plaintext env config.** Putting the token itself
   behind 1P + Keychain means there is no point in the workflow where the
   raw `ops_...` value sits in a file under version control, even in
   `.local`. Rotation in 1P + `dotfiles secret refresh` is the whole flow.
3. **Dedicated `Agents` vault recommended but not enforced.** The spec
   documents the blast-radius concern (section below) but does not force a
   vault layout; different users have different tolerance for blast radius
   vs. operational simplicity.
4. **Machine must have 1P to use this.** On `use_1password: false` machines
   (e.g. headless CI boxes), `secrets.fish.tmpl` skips the whole block.
   No breakage; agents on those machines fall back to whatever the CI
   environment injects.
5. **No automatic plan detection.** If the user's 1P plan does not support
   service accounts, `op service-account create` fails at the web console
   and the spec's setup step 1 stops there; the dotfiles repo cannot and
   should not detect this.

## Blast radius (be explicit)

A service account token is **one credential that reads every vault the
service account can see**. The Keychain entry on any given machine therefore
holds a broader key than a single per-secret cache entry.

Mitigations, ranked by cost/benefit:

| Mitigation | Cost | Benefit |
|---|---|---|
| Scope the service account to a dedicated `Agents` vault | Minimal (create one vault) | Compromise of the token leaks only agent-relevant secrets, not the user's personal vault |
| Rotate the token on a schedule (web console + `dotfiles secret refresh`) | Manual, every few months | Bounds the window of a silent leak |
| Watch rate-limit usage with `op service-account ratelimit` | Zero, occasional check | Detects abnormal consumption (possible leak or runaway agent) |
| Revoke + re-issue on suspicion | 5 minutes | Full containment if the token is believed leaked |

The Keychain cache itself is encrypted at rest by macOS and per-login-account,
so offline disk theft does not leak the token. The threat model we're
guarding against is "malicious process running as the same user reads the
env var and exfiltrates it", same threat as for `ANTHROPIC_API_KEY` or any
other long-lived personal credential. This is accepted; the alternative
(per-call biometric) does not work for agent subprocesses by design.

## Failure modes

| Scenario | Behaviour |
|---|---|
| Machine has `use_1password: false` | `secrets.fish.tmpl` skips the block; `OP_SERVICE_ACCOUNT_TOKEN` never set; agents that need it fail cleanly with an empty env var |
| `op://...sa-<purpose>/credential` item deleted in 1P | `secret-cache-read` falls through to `op read`, which fails; `OP_SERVICE_ACCOUNT_TOKEN` stays empty; already-cached Keychain value remains usable until refreshed |
| Token rotated in 1P but Keychain still cached | Stale token in env; child `op read` calls return 401. Fix: `dotfiles secret refresh OP_SERVICE_ACCOUNT_TOKEN && exec fish` |
| Token revoked | Same as rotated-but-not-refreshed; 401 errors until user refreshes |
| Headless/SSH/Codespaces | Biometric unlock unavailable → first `op read` for the token fails → token never caches → agents run in degraded mode. Workaround: inject `OP_SERVICE_ACCOUNT_TOKEN` directly into the CI env without going through `secret-cache-read` |
| Plan downgrade that removes service account support | Token keeps working until the service account is deleted server-side; after deletion, 401 responses |

## Files changed

**New:**
- `docs/specs/S-42-service-account-agent-auth.md`: this spec

**Modified (documentation only):**
- `CLAUDE.md`: note the service account pattern in the secret injection
  section; keep `secret-cache-read` and `onepasswordRead` descriptions intact
- `docs/guide.md`: add a "Service account for agent subprocess `op read`"
  subsection under §6 Secrets management
- `docs/sync-log.md`: hostname-tagged entry recording rollout on this machine
- `home/.chezmoidata/secrets.toml`: registers `OP_SERVICE_ACCOUNT_TOKEN`
  (done via `dotfiles secret add`; the entry is a committed `op://` reference,
  not a secret value)

**Not changed (intentionally):**
- `home/dot_local/bin/executable_secret-cache-read`: works as-is
- `home/dot_config/fish/conf.d/secrets.fish.tmpl`: works as-is
- `home/dot_config/fish/functions/dotfiles.fish`: `dotfiles secret *` subcommands handle this without special-casing

## Rollout notes

- Only machines that (a) have 1Password configured and (b) run
  `dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN ...` get the behaviour.
  Other machines are untouched.
- First fish login after registration triggers one biometric prompt to read
  the token from 1P. All subsequent logins are silent.
- Token value never appears in the repo, in chezmoi state, or in rendered
  config files. Only the `op://` reference is committed.

## Testing

Run the same verification flow as S-35:

```fish
# 1. Rendered secrets.fish includes the new var (no secret value present)
chezmoi execute-template < home/dot_config/fish/conf.d/secrets.fish.tmpl | grep OP_SERVICE_ACCOUNT_TOKEN

# 2. Shell startup populates env (after one interactive biometric)
exec fish
echo $OP_SERVICE_ACCOUNT_TOKEN | head -c 4     # should print "ops_"

# 3. Subprocess op read works headlessly
bash -c 'op read op://<scoped-vault>/<item>/<field>'

# 4. Claude Code inherits the token
#    (launch claude from this shell; inside a session, Bash tool runs
#     op read and returns the value)
```

Failure of step 3 with `OP_SERVICE_ACCOUNT_TOKEN` set and non-empty means
either the token is expired/revoked or the service account is not scoped to
the vault being read.

## What's explicitly NOT supported

- Automated service account creation from the dotfiles. The user creates
  the service account in the 1P web console; this is a conscious
  security-review gate, not an oversight.
- Automatic rotation. Rotation is a manual 1P web action + per-machine
  `dotfiles secret refresh`.
- Per-project service account tokens. If the user wants separate tokens
  for different agents/projects, they register multiple variables
  (`OP_SERVICE_ACCOUNT_TOKEN_TRADING`, `OP_SERVICE_ACCOUNT_TOKEN_OPS`) and
  teach the agent which env var to use. `op` itself only honours
  `OP_SERVICE_ACCOUNT_TOKEN`, so multi-token setups require a wrapper.
