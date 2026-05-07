# 1Password workflow + analysis

This doc is the single source of truth for how 1Password is wired into this dotfiles repo: the mental model, the dual-mode design, the day-to-day commands, the trade-offs we accepted, and the spec chain that got us here.

If you only read one section, read **[Mental model](#mental-model)** then **[Day-to-day](#day-to-day)**. Everything else is depth on demand.

---

## Mental model

Three resolution patterns coexist. Pick the right one per secret.

| Pattern | Resolves at | Triggers 1P? | Used for |
|---|---|---|---|
| **Apply-time** (`onepasswordRead` in `.tmpl`) | `chezmoi apply` | Yes, every apply | Files that need the secret baked in at write time. `dot_gitconfig.tmpl`, `dot_config/zed/settings.json.tmpl`. |
| **Lazy + Keychain** (`secret-cache-read` from `secrets.fish`) | First fish login on a new machine | First login only; cached forever after | Env vars: `CLOUDFLARE_API_TOKEN`, `R2_*`, `OP_SERVICE_ACCOUNT_TOKEN`. |
| **Service account bearer** (token in env) | Anytime a process calls `op` with the token in env | Never (no biometric, bearer auth) | Headless `op read` from agent subprocesses. |

The third pattern is the interesting one. It powers Claude Code's Bash tool reading 1P mid-session, but it also breaks daily interactive `op` if not handled carefully. The **dual-mode design** (S-49) makes both work simultaneously.

### The dual-mode design (S-49)

```
fish login → set -gx OP_SERVICE_ACCOUNT_TOKEN ... (auto-loaded from secrets.toml)
   │
   ├─ Interactive `op vault list` typed at fish prompt
   │      → fish function `op` (defined in op.fish) intercepts
   │      → status is-interactive = true
   │      → env -u OP_SERVICE_ACCOUNT_TOKEN command op vault list
   │      → biometric / desktop-integration auth → all your vaults
   │
   └─ Subprocess (zsh, bash, scripts, claude, …)
         → no fish function in scope (different shell)
         → calls `op` binary directly
         → bearer auth via env var → SA-scoped, headless, no prompt
```

The key insight: **the interceptor is a fish function**. Fish functions are only visible in fish. Subprocess shells (Claude Code's Bash tool runs zsh) don't see it and call the binary directly. Each layer behaves correctly without coordination.

---

## Day-to-day

### Daily commands work as expected

```fish
op vault list                    # all your vaults (biometric)
op item list --vault Private     # full Private contents
op read op://Private/foo/bar     # any vault, any item
```

### Agents inside Claude Code work as expected

When a Claude Code session needs ad-hoc `op read op://...` from its Bash tool, it just works. No prefix, no wrapper, no setup beyond the one-time SA token registration. The token is in env, zsh subshell sees it, `op` uses bearer auth.

### Bypass the interceptor when needed

```fish
command op vault list           # call binary directly (skips fish function)
with-agent-token op vault list  # explicit per-invocation wrapper (debug)
```

Both return the SA-scoped subset, useful for "what does the agent actually see?" debugging.

---

## Setup (fresh machine)

1. **Install desktop + CLI**
   ```fish
   brew install 1password 1password-cli
   ```
   Open the desktop app, sign in, enable `Settings → Developer → Connect with 1Password CLI`.

2. **Verify CLI sees your account**
   ```fish
   op account list      # shows your account URL
   op vault list        # shows all vaults
   ```

3. **Run `chezmoi init` and answer prompts**
   - `use_1password`: yes
   - `op_account`: e.g. `dwarvesv.1password.com`
   - `op_vault`: default vault, e.g. `Private`

4. **Create the service account** (one-time per user, not per machine)
   - 1P web → `Developer Tools → Service Accounts → Create`
   - Read-only access to the agent-readable vaults (today: `Trading`; per S-46 also `Infras` once you're ready)
   - Copy the `ops_...` token; store as a 1P item:
     `op://Private/op-service-account-trading/credential`
     (Or any path; update the ref in `home/dot_config/fish/functions/with-agent-token.fish` if different.)

5. **First fish login** resolves all auto-loaded secrets via `secret-cache-read`. One biometric prompt per registered secret on the first shell only; Keychain caches forever.

6. **Verify dual-mode**
   ```fish
   echo $OP_SERVICE_ACCOUNT_TOKEN | head -c 4   # ops_  (auto-loaded)
   op vault list | wc -l                         # all vaults (interactive biometric)
   bash -c 'op vault list' | wc -l               # SA-scoped (subprocess bearer)
   ```

---

## Adding / removing / rotating secrets

### Add an env-var-style secret
```fish
dotfiles secret add OPENAI_API_KEY "op://Private/OpenAI/credential"
exec fish    # reload to pick up the new env var
```
The command creates the 1P item if missing (prompts for value), writes the binding to `secrets.toml`, runs `chezmoi apply` (scoped to `secrets.fish` per S-48), and auto-commits the registry change.

### Rotate a token
Edit the value in 1P (web or app). Then on each machine:
```fish
dotfiles secret refresh OPENAI_API_KEY
exec fish
```
No repo change. The `op://` reference is the same; only the value behind it changed.

### Remove a secret
```fish
dotfiles secret rm OPENAI_API_KEY
```

### List + cache status
```fish
dotfiles secret list
# Registered secrets (cache status from macOS Keychain):
#   [cached] CLOUDFLARE_API_TOKEN → op://Private/Cloudflare API Token/credential
#   [cached] OP_SERVICE_ACCOUNT_TOKEN → op://Private/op-service-account-trading/credential
#   [ empty] NEW_TOKEN → op://Private/New/credential
```

---

## Vault tiering (S-46)

The service account is currently scoped to one vault (`Trading`). When agent capabilities expand and platform/deploy creds enter the picture, follow S-46's three-tier model:

| Tier | Contents | SA scope |
|---|---|---|
| **Primary domain** (e.g. `Trading`) | Domain-specific runtime secrets | read-only |
| **Infra** (e.g. `Infras`) | Platform tokens, deploy credentials, cross-cutting agent-infra | read-only |
| **Personal** (`Private`) | SA's own token, owner-personal items | **no SA access** |

Why the personal vault must be SA-unreadable: defense in depth. A compromised agent must not be able to re-emit its own credential or pivot to personal items. Keep the SA token's storage location outside SA scope.

When you're ready to broaden: add `Infras` to the SA's scope in 1P web admin (read-only), then move platform-cred 1P items into `Infras` and update the `op://` refs in `secrets.toml` accordingly.

Don't add personal vaults to SA scope. Don't run a second SA — see S-46 §"Why not a second service account."

---

## Trade-offs accepted

| Trade-off | Rationale |
|---|---|
| Token is in shell env (S-49 model) | Same blast-radius profile as the original S-42. Any process running as you can read the env var. The win: agents work without ceremony, daily UX unaffected. |
| Auto-load adds a few hundred ms to first fish login on a new machine | One-time per machine. Subsequent logins are silent (Keychain hit). Acceptable. |
| Wrapping `op` in fish adds ~1 ms per invocation | Negligible. Worth it for the cleanly-separated semantics. |
| Different behavior for `op` typed at prompt vs `op` in a script | Intentional: scripts are the "agent" case (non-interactive, want bearer). If a fish script needs biometric, use `command op` to bypass the function. Documented in `op.fish` itself. |
| SA scoped to `Trading` only today | Matches current agent need. Broaden per S-46 when infra workloads start needing `op read`. |

---

## Multi-machine (Air, Mini, iOS SSH)

The model above describes a single machine with a GUI session. When you have
two daily-driver Macs sharing dotfiles (Air + Mini) and you operate the Mini
mostly over SSH, two specific things change: the `is-login` gate (so non-
interactive SSH login shells also load secrets) and a one-time Keychain seed
from the GUI machine to the headless one. iOS SSH clients (Termius, Blink)
ride on the same model with one gap: outbound `git push` from the Mini needs
a per-iOS-app SSH key since iOS has no 1Password SSH agent to forward.

Full design, gate flow, per-environment matrix, web3 hardening rule, and
recipes live in [`1password-multi-machine.md`](1password-multi-machine.md).
The change list that ships this is [S-51](specs/S-51-multi-machine-sa-access.md).

---

## Troubleshooting

**"`op vault list` only shows Trading"**
You're seeing the SA-scoped view. Check:
- `type op` in fish — should be a function (`op.fish`). If it says "external", the interceptor isn't loaded. Run `chezmoi apply` and `exec fish`.
- Make sure `status is-interactive` is true. If you're running `fish -c '...'` (non-interactive), the interceptor lets the token through; that's by design.

**"`op read` from a Claude Code Bash tool returns empty"**
- Confirm token is in env: launch via plain `claude` from a fresh fish shell. From inside, run `Bash:echo $OP_SERVICE_ACCOUNT_TOKEN | head -c 4` — should print `ops_`.
- If empty, check `dotfiles secret list` — `OP_SERVICE_ACCOUNT_TOKEN` should show `[cached]`. If `[ empty]`, run `exec fish` to trigger biometric and cache it.

**"`chezmoi apply` triggers 1P popups every time"**
Some secret is using apply-time `onepasswordRead` instead of lazy `secret-cache-read`. Grep for it: `grep -rn 'onepasswordRead' home/`. If the secret could be lazy-loaded, migrate it to `secrets.toml` registration.

**"Token rotation didn't take effect"**
You updated the 1P item but Keychain has the old value. Run `dotfiles secret refresh OP_SERVICE_ACCOUNT_TOKEN` and `exec fish`. The `with-agent-token` wrapper picks up the refreshed value on its next call.

**"Using `/dotfiles-sync` and SSH backup check reports 0 keys"**
Already fixed (post-S-49). The skill now drops `OP_SERVICE_ACCOUNT_TOKEN` before running `dotfiles ssh audit` so it sees the user's full vault list.

---

## Spec chain (history)

| Spec | What | Status |
|---|---|---|
| [S-35](specs/S-35-local-pattern-and-lazy-secrets.md) | Lazy resolution + Keychain cache for env-var secrets | done |
| [S-42](specs/S-42-service-account-agent-auth.md) | Service-account auto-load for agent subprocess `op read` | superseded by S-47 |
| [S-43](specs/S-43-sync-secret-cache-visibility.md) | Surface registered-but-uncached secrets in sync + doctor | done |
| [S-45](specs/S-45-secret-refresh-no-echo.md) | Stop echoing secret values in `secret refresh` (post-leak fix) | done |
| [S-46](specs/S-46-three-vault-model-for-agent-infra-secrets.md) | Multi-vault tiering pattern | proposed (apply when infra-cred workload arrives) |
| [S-47](specs/S-47-agent-token-opt-in-wrapper.md) | Opt-in wrapper (intermediate redesign) | amended by S-49 |
| [S-48](specs/S-48-secret-add-narrow-apply-scope.md) | Narrow `chezmoi apply` scope in `dotfiles secret add/rm` | done |
| [S-49](specs/S-49-dual-mode-op-via-fish-interceptor.md) | **Dual-mode `op` via fish interceptor (current model)** | done |
| [S-51](specs/S-51-multi-machine-sa-access.md) | **Multi-machine extension** (`is-login` gate + `dotfiles secret push`) | done |
| [S-52](specs/S-52-secrets-architecture-synthesis-doc.md) | **Synthesis doc** mapping the whole secrets problem space | done |

For the **whole-surface map** (every credential class × device × path,
spec-to-slice index, threat model, open-questions catalog), see
[`secrets-architecture.md`](secrets-architecture.md). That doc is the
entry point if you're trying to figure out where a future change should
go; this doc is the day-to-day manual.

The arc S-42 → S-47 → S-49 happened in this order:

1. **S-42 (auto-load)**: token in env for every shell. Agents work; daily `op` is scoped down.
2. **S-47 (opt-in wrapper)**: token removed from auto-load; `with-agent-token <cmd>` injects per-launch. Daily `op` works; agents only work when launched with the wrapper.
3. **S-49 (dual-mode)**: token auto-loaded again, but a fish `op` function strips it for interactive calls. Both work, no wrapper required at launch. The wrapper is kept as a debug escape hatch.

S-48 was a tooling fix discovered during S-47 verification: `dotfiles secret add` would silently drift source/target on chezmoi-apply failure. Out of the spec arc but related.

---

## Operational references

- **Architecture rationale:** `CLAUDE.md` §"Secret injection (three patterns, one backend)"
- **User-facing customization:** `docs/guide.md` §"6. Secrets management"
- **Sync history per machine:** `docs/sync-log.md` (look for hostname-tagged entries)
- **Multi-vault migration runbook:** `docs/operations/2026-04-1password-infra-vault-migration.md`
