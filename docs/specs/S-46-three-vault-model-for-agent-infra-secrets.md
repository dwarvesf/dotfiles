---
id: S-46
title: Multi-vault tiering for 1Password service-account scope
type: feature
status: done
date: 2026-04-24
implemented: 2026-05-08
---

# S-46: Multi-vault tiering for 1Password service-account scope

## Problem

[S-42](S-42-service-account-agent-auth.md) established the single-vault service-account pattern: one `OP_SERVICE_ACCOUNT_TOKEN`, scoped read-only to one dedicated vault, bearer-auth for agent subprocesses. The pattern holds until a second class of secret appears that:

- Needs runtime `op read` from agent code (not just env-var inherit at shell start per [S-35](S-35-local-pattern-and-lazy-secrets.md)), AND
- Has a different blast-radius profile from the primary vault (e.g. platform/deploy credentials that widen a leak from "drain one domain" to "push malicious Workers, poison storage buckets, pivot to CI")

At that point the natural reach is one of two tempting wrong answers:

1. **Widen the SA's scope to include the new vault.** Collapses the blast radius: one leaked token now covers both tiers. Violates the least-privilege motivation of S-42.
2. **Run a second SA scoped to the new vault.** `op read` consumes one `OP_SERVICE_ACCOUNT_TOKEN` per process. Two SAs require a wrapper that picks per-read, breaking S-42's zero-new-code property. Also doubles rotation cadence and Keychain-cache surface.

## Non-goals

- **Moving the SA's own token.** It must live in a vault the SA cannot read (defense-in-depth: a compromised agent cannot self-persist or re-emit its own credentials).
- **Adopting 1Password Environments.** Environments solve same-logical-name-different-tier indirection; this pattern uses distinct names per tier. Revisit only when item count forces tier indirection.
- **Migrating owner-personal secrets out of the personal tier.** Passwords, authenticator backups, non-infra notes stay out of SA scope entirely.
- **Automated vault creation.** 1P vault creation + SA scope changes are web-UI operations. This pattern assumes the owner performs them manually.

## Solution

Introduce an **N-vault tier model**, all scoped to the single SA:

| Tier | Contents | SA scope | Rationale |
|---|---|---|---|
| **Primary domain** | Domain-specific runtime secrets (exchange keys, strategy inputs, domain webhook tokens) | read-only | Original S-42 target |
| **Infra / deploy** (new) | Platform API tokens, storage credentials, deploy tokens, cross-cutting agent-infra | read-only | Widens SA coverage without collapsing blast radius into the primary domain |
| **Personal** | SA's own token, owner-personal items | **no SA access** | Defense-in-depth (SA can't read own storage) + protects owner-personal |

The SA is scoped to `{Primary, Infra}`, both read-only. Adding a new infra secret = add to Infra vault, no scope change. Adding a new primary-domain secret = add to Primary vault, no scope change. SA token stays unreachable.

### Vault placement heuristic

For any new secret, decide by asking in order:

1. **Is it the SA's own token?** → Personal vault. Always. No exceptions.
2. **Is it owner-personal?** (Passwords, backup codes, non-infra notes.) → Personal vault.
3. **Does the agent `op read` it at runtime?**
   - No → Personal vault is acceptable (agent inherits value via env at shell start per S-35; no vault read needed).
   - Yes → must live in SA scope (Primary or Infra).
4. **Is it tied to the primary domain?** (Runs during domain workflows; a leak harms the domain first.)
   - Yes → Primary vault.
   - No (platform/deploy credential, cross-cutting infra) → Infra vault.

### Why not a second service account

A second SA scoped to `Infra` alone would narrow each token's blast radius further. Rejected because:

- `op read` takes one `OP_SERVICE_ACCOUNT_TOKEN` per process. Picking between two requires a wrapper that encodes vault→token mapping, new code in every call site, or a fish-function indirection. Violates S-42's zero-new-code property.
- Two SAs = two rotation cadences = two Keychain entries = more operational surface. Current scale doesn't warrant it.
- A compromise at Infra scope alone is still a full platform-credential compromise. Marginal security benefit vs single-SA-with-{Primary, Infra} is low relative to the operational cost.

### When to revisit

Move to multiple SAs (not just multiple vaults) if any of:

- A future credential grants privileges orders of magnitude more dangerous than the current Infra set (e.g. organization-admin tokens).
- Multiple agent classes emerge that need disjoint infra subsets.
- The vault count reaches the point where 1P Environments become necessary (same logical name across ≥5 tiers).

## Testing / Done definition

For any application of this pattern, verify from a fresh shell with `OP_SERVICE_ACCOUNT_TOKEN` loaded:

- `op read op://<Primary>/<known-item>/credential` returns the value.
- `op read op://<Infra>/<known-item>/credential` returns the value.
- `op read op://<Personal>/<SA-token-item>/credential` returns a scope-denial error (SA remains blind to its own storage).
- S-35 env-var consumers of Infra secrets continue to work (no regression on the lazy-resolve path).
- The SA's scope detail page in 1P web UI lists exactly the two intended vaults, both Read-only.

Shipping-side checklist (per-owner, per-migration):

- [ ] Consumer repos that reference the SA's scope are updated with the new vault(s).
- [ ] `docs/operations/` entry recording the specific migration (item moves, SA scope change, cache refresh) is captured.
- [ ] `docs/sync-log.md` entry appended per [S-44](S-44-spec-status-housekeeping.md).
- [ ] This spec's `status` flipped to `done` once the first application ships.

## References

- [S-42](S-42-service-account-agent-auth.md): parent pattern, single-vault SA for agent subprocess auth. This spec extends it to N vaults.
- [S-35](S-35-local-pattern-and-lazy-secrets.md): pre-registered secret inherit path; unaffected by multi-vault tiering.
- [`docs/operations/`](../operations/): where specific migration runs and SA rotations are logged. The author's first application of this pattern is recorded there.

---

**Status note**: done. Shipping = the owner applies the pattern to their own 1P setup. Migration record below.

## Implementation

Applied 2026-05-08 with these literal vault names:

| S-46 tier | Literal name | Contents |
|---|---|---|
| Primary domain | `Trading` (newly created) | `1inch-api`, `binance-live`, `binance-testnet`, `helius-solana-mainnet`, `trading-hot-seed` |
| Infra / deploy | `Toolkit` (renamed from old `Trading`) | `cf-*`, `notion-*`, `discord-*`, `telegram-*`, `vps-mon-*`, `mac-*`, `hermes-*`, etc. |
| Personal | `Private` (unchanged) | `op-service-account-ops` SA bootstrap, owner-personal items |

SA renamed `op-service-account-trading` → `op-service-account-ops`, bearer key rotated, granted Read on `{Toolkit, Trading}`. Items `Cloudflare R2` and `Cloudflare API Token` renamed to kebab-case `cf-r2` and `cf-api-token` during the split.

Migration record: [`docs/operations/2026-05-08-op-vault-toolkit-trading-split.md`](../operations/2026-05-08-op-vault-toolkit-trading-split.md).

Code commits across 5 repos (481 line changes / 164 files; all on local branches, none pushed at time of writing):

- `tieubao/dotfiles@feat/multi-machine-op`: `7e2be47` (runtime `secrets.toml` flip) + `35d2526` (docs/SPEC sweep) + this commit (S-46 closure).
- `tieubao/ops-toolkit@refactor/op-vault-split`: `7954df6` — 65 files.
- `tieubao/dfoundation@refactor/op-vault-split`: `952abcd` — 30 files.
- `tieubao/trading@refactor/op-vault-split`: `e9ca4f8` — 46 files (5 keepers preserved at `op://Trading/<x>`).
- `tieubao/event-bridge@refactor/op-vault-split`: `9fab388` — 12 files incl. `wrangler.toml`.

The April planning doc (`2026-04-1password-infra-vault-migration.md`) was never executed as drafted — its planned `Infra` vault did not land. Today's `Toolkit`/`Trading` split is the actual implementation; April record marked superseded.
