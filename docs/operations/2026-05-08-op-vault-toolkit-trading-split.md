---
title: 1Password vault split — Trading→Toolkit + new Trading + SA rotation
date: 2026-05-08
related_spec: S-46
status: done
supersedes: 2026-04-1password-infra-vault-migration.md
---

# 1Password vault split (May 2026)

First real application of the [S-46](../specs/S-46-three-vault-model-for-agent-infra-secrets.md) multi-vault tiering pattern. The April migration record (`2026-04-1password-infra-vault-migration.md`) drafted a `Private` → `Infra` move that was never executed as planned; the actual reorg landed today with different naming.

## Starting state (pre-2026-05-08)

- Single SA vault `Trading` (read-only) holding everything: actual trading creds (`binance-*`, `1inch-api`, `helius-*`, `trading-hot-seed`) **plus** ops/infra creds (`cf-*`, `notion-*`, `discord-*`, `telegram-*`, `vps-mon-*`, `mac-*`, `hermes-*`, etc.). Vault name was a misnomer; `dfoundation/infra/topology.md` already documented "*despite the name, it's the ops vault*".
- SA name `op-service-account-trading` scoped to `{Trading}`.
- 4 cached secrets in laptop Keychain: `OP_SERVICE_ACCOUNT_TOKEN`, `CLOUDFLARE_API_TOKEN`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`.
- Symptom that triggered the work: fish login shell ~2.6s. Root cause: `op://Private/Cloudflare R2/...` references in `secrets.toml` failed under SA scope (1.2s × 2 cache misses per login). See morning's commits `7c4ffc4` (refs migrated Private→Trading) and `6db9ad3` (negative-cache wrapper).

## Target state (post-2026-05-08)

- **Two SA vaults**, dual-scoped:
  - `Toolkit` (renamed from old `Trading`) — Infra tier per S-46. All ops/infra items.
  - `Trading` (newly created) — Primary domain tier per S-46. Holds 5 actual trading items: `1inch-api`, `binance-live`, `binance-testnet`, `helius-solana-mainnet`, `trading-hot-seed`.
- **Items renamed inside Toolkit**: `Cloudflare R2` → `cf-r2`, `Cloudflare API Token` → `cf-api-token` (kebab-case alignment with the rest of Toolkit).
- **SA renamed** `op-service-account-trading` → `op-service-account-ops`, **bearer key rotated**, granted Read on `{Toolkit, Trading}`.
- SA token continues to live in `op://Private/op-service-account-ops/credential` (Personal vault unreachable to SA — defense-in-depth preserved per S-46 non-goal #1).

## Execution

### 1P web UI (owner action, ~5 min)

1. Vaults → rename `Trading` → `Toolkit`.
2. Vaults → create `Trading` (fresh).
3. Move 5 items from `Toolkit` → `Trading`: `1inch-api`, `binance-live`, `binance-testnet`, `helius-solana-mainnet`, `trading-hot-seed`.
4. Rename items in `Toolkit`: `Cloudflare R2` → `cf-r2`, `Cloudflare API Token` → `cf-api-token`.
5. Service Accounts → `op-service-account-trading` → rename to `op-service-account-ops`; rotate key; grant Read on `Toolkit` + `Trading`.
6. Paste new bearer value into `op://Private/op-service-account-ops/credential` (the SA's bootstrap item). **Easy to forget**; the rotated bearer must replace the old one in the Personal-vault item or the laptop's biometric path can't bootstrap subsequent sessions.

### Laptop (Phase 0+1+2) — fully scripted

- Edit `home/.chezmoidata/secrets.toml`: 4 ref flips (`Private/op-service-account-trading` → `Private/op-service-account-ops`; `Trading/Cloudflare API Token` → `Toolkit/cf-api-token`; `Trading/Cloudflare R2/{username,credential}` → `Toolkit/cf-r2/{username,credential}`).
- `chezmoi apply` → regenerate `~/.config/fish/conf.d/secrets.fish`.
- Flush stale Keychain entries for all 4 cached secrets via `security delete-generic-password`.
- Bulk migrate 5 repos via `/tmp/migrate-op-refs.py` (Python, regex-with-keeper-exclusion + literal-rename pre-pass for items with spaces). Rules:
  - `op://Trading/<x>` where `<x>` ∉ {1inch-api, binance-live, binance-testnet, helius-solana-mainnet, trading-hot-seed} → `op://Toolkit/<x>`.
  - `op://Trading/Cloudflare R2` → `op://Toolkit/cf-r2`.
  - `op://Trading/Cloudflare API Token` → `op://Toolkit/cf-api-token`.
  - `op-service-account-trading` → `op-service-account-ops`.
- One commit per repo, conventional message:
  - `tieubao/dotfiles@feat/multi-machine-op` `7e2be47` (runtime) + `35d2526` (docs sweep).
  - `tieubao/ops-toolkit@refactor/op-vault-split` `7954df6` (65 files).
  - `tieubao/dfoundation@refactor/op-vault-split` `952abcd` (30 files).
  - `tieubao/trading@refactor/op-vault-split` `e9ca4f8` (46 files; 5 keepers preserved at `op://Trading/`).
  - `tieubao/event-bridge@refactor/op-vault-split` `9fab388` (12 files incl. `wrangler.toml`).
- Total: **481 line changes across 164 files**.

### Mac Mini (Phase 3) — owner ran in separate chat

Per `~/workspace/tieubao/ops-toolkit/_meta/LAB_LOG.md` entry (2026-05-08 late afternoon):

- Substrate dirs `tools/{mac-mini-substrate,mac-backup}/` rsync'd from `tieubao`'s clone (HEAD `7954df6`) into `server`'s, via `sudo -u server rsync` (local, since the chat ran on the Mini).
- Surgical `sed` on `dfoundation/infra/substrate/mac-mini/hermes-insights-digest.sh` with `.bak.pre-vault-split-2026-05-08` recovery point.
- Smoke-fired `mini.upgrade-check` LaunchDaemon: exit 0, digest built (1800 chars), Discord post sent (1840 chars).
- Surfaced finding: **all three runtime scripts have static-file fallbacks** (`/Users/server/.config/foundation.d/discord-webhook`, `~/.hermes/.env`). Daemon-context `op read` was *never* load-bearing because `server` has no 1P session in the daemon-equivalent env (`env -i PATH=... HOME=... op read` returns "No accounts configured"). Fallbacks silently absorbed every previous post-migration fire. The fix matters when fallbacks rotate or when a future daemon skips the fallback pattern.

## Consumer-repo updates

| Repo | Branch | Commit | Files | Lines |
|---|---|---|---|---|
| `tieubao/dotfiles` | `feat/multi-machine-op` | `35d2526` (+ runtime in `7e2be47`) | 11 | 15 |
| `tieubao/ops-toolkit` | `refactor/op-vault-split` | `7954df6` | 65 | 184 |
| `tieubao/dfoundation` | `refactor/op-vault-split` | `952abcd` | 30 | 87 |
| `tieubao/trading` | `refactor/op-vault-split` | `e9ca4f8` | 46 | 145 |
| `tieubao/event-bridge` | `refactor/op-vault-split` | `9fab388` | 12 | 50 |

None pushed at time of writing.

## Verification checklist

- [x] `op vault list` under SA auth returns both `Toolkit` and `Trading`.
- [x] `op read op://Toolkit/cf-r2/credential` returns the value (verified hex string).
- [x] `op read op://Trading/binance-live` (item-get) succeeds — proves dual-vault scope.
- [x] `op read op://Private/op-service-account-ops/credential` succeeds via biometric (laptop + Mini both); SA bearer auth correctly returns 403 for the same ref (defense-in-depth preserved).
- [x] Fish login shell ≤200ms steady-state on laptop (was 2.6s pre-migration). First post-migration login ~8s while re-seeding cache; subsequent ~100ms.
- [x] Trading-keeper refs preserved across all 5 repos (verified by exclusion grep — only `binance-live` + `binance-testnet` remain at `op://Trading/...` since the other 3 keepers had no URI references in any repo).
- [x] No `op-service-account-trading` references in any repo or under `~/.config`/`~/.local`.
- [x] Mac Mini deployed runtime files updated; `mini.upgrade-check` smoke-fired green.
- [x] S-46's status flipped `proposed` → `done` (this commit cycle).
- [x] `docs/sync-log.md` entry appended (this commit cycle).

## Decisions / lessons

1. **Vault naming**: literal `Toolkit` / `Trading` chosen over S-46's generic "Infra" / "Primary". `Toolkit` reflects current contents (cf, notion, discord, telegram, vps-mon, mac, hermes — generic ops tooling); `Trading` retained the historically-correct semantic name for the actual trading items.
2. **History-rewrite policy**: owner chose "update everywhere" — `decisions.md`, `INGEST_LOG.md`, `HANDOFF.md`, `_meta/handoff-*.md`, incidents archive across all repos rewritten to use new vault names. Accepted tradeoff: those entries now describe past events with vault names that didn't exist at the time. Cleanest visually; historically slightly dishonest. Audit pass recommended on dfoundation+trading decision logs before pushing if this matters more than first thought.
3. **SA token bootstrap stays in Personal**: did NOT migrate `op://Private/op-service-account-ops/credential` to either SA-readable vault. Confirms S-46 non-goal #1 (defense-in-depth: compromised SA cannot self-emit credentials). Comment block added in `secrets.toml` so future-cleanup doesn't quietly regress this.
4. **Negative-cache wrapper interaction**: today's earlier commit (`6db9ad3`, negative-cache in `secret-cache-read`) interacted with the migration in an unexpected way — when the first post-rotation login briefly inherited a stale `OP_SERVICE_ACCOUNT_TOKEN` from the parent shell's env, the wrapper's `op read` failed with 403 and wrote `.miss` markers for the 3 ops creds, blocking subsequent re-fetch. Mitigation: `mv ~/.cache/secret-cache-read/*.miss /tmp/` to clear, then re-drive login. Worth keeping in mind for any future SA rotation: the wrapper's protection against bad refs becomes a soft trap when the *token itself* is what just changed.
5. **Daemon-context `op read` is null on Mini**: see Phase 3 above. Static-file fallbacks have been carrying the actual load. Implication: don't assume a Mini LaunchDaemon will pick up new vault refs just because they resolve in interactive `tieubao` shell — verify the daemon path explicitly.

## Rotation calendar

Next SA rotation cadence kept on the existing 90-day cycle. Today's rotation counts as the May rotation; next would be ~2026-08-06. Calendar reminder lives in `tieubao/trading/operations/broker-access.md` "Service account + infra secret rotation" table — that file was migrated in `e9ca4f8` (vault names updated; rotation date unchanged from prior April reset).

## Open follow-ups

Captured in the laptop-side handoff (next chat):

1. Push the 5 `refactor/op-vault-split` branches (and `feat/multi-machine-op` in dotfiles).
2. Decide on `tieubao/trading` WIP stash (`engine/observability/{discord_dispatch,fetchers}.py` adds shutil + path resolver; conflicts with this branch on URI lines — keep new `op://Toolkit/...`).
3. Audit history rewrites in `decisions.md` / `INGEST_LOG.md` / archive folders before pushing if "update everywhere" feels too aggressive in retrospect.
4. Commit the `_meta/LAB_LOG.md` Phase 3 entry in `ops-toolkit` (currently working-tree dirty).
