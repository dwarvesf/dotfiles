---
title: 1Password Infra vault migration
date: 2026-04-24
related_spec: S-46
status: superseded
superseded_by: 2026-05-08-op-vault-toolkit-trading-split.md
---

> **Superseded.** This planning doc proposed a `Private` → `Infra` move. It was
> never executed as drafted. The actual S-46 implementation landed 2026-05-08
> with different naming (`Toolkit` instead of `Infra`, plus a separate new
> `Trading` vault for the 5 trading keepers). See the linked record for what
> actually happened.


# 1Password Infra vault migration (April 2026)

Personal migration record for applying the [S-46](../specs/S-46-three-vault-model-for-agent-infra-secrets.md) multi-vault tiering pattern to the author's 1P setup.

## Starting state

- SA name: `trading-agent`
- Current scope: `Trading` (read-only)
- Infra secrets (`cloudflare-api-token`, `r2-*` access keys) currently in `Private` → reach the agent only via env-var inherit (S-35). Agent code that wants to `op read` them at runtime fails because `Private` is out of SA scope by design.

## Target state

- New vault: `Infra`
- Items moved `Private` → `Infra`: `cloudflare-api-token`, `r2-access-key-id`, `r2-secret-access-key`
- SA scope: `Trading + Infra` (both read-only)
- SA token remains in `Private` (unreachable by SA itself; defense-in-depth preserved)

## Execution steps

1. **1P web UI** → Vaults → Create vault `Infra`.
2. **1P web UI** → move items `cloudflare-api-token`, `r2-access-key-id`, `r2-secret-access-key` from `Private` → `Infra`.
3. **1P web UI** → Developer Tools → Service Accounts → `trading-agent` → extend scope to include `Infra:read_items`. Verify SA detail page lists `Vaults (2)` with `Trading` + `Infra`, both Read.
4. Update `.chezmoidata/secrets.toml`:
   ```toml
   CLOUDFLARE_API_TOKEN   = "op://Infra/cloudflare-api-token/credential"
   R2_ACCESS_KEY_ID       = "op://Infra/r2-access-key-id/credential"
   R2_SECRET_ACCESS_KEY   = "op://Infra/r2-secret-access-key/credential"
   ```
5. `chezmoi apply` to re-render `~/.config/fish/conf.d/secrets.fish`.
6. `dotfiles secret refresh CLOUDFLARE_API_TOKEN R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY` to invalidate Keychain cache entries that still point at the old `op://Private/...` paths.
7. `exec fish`. Touch ID fires once per refreshed entry; new paths cached.

## Consumer-repo updates

- `tieubao/trading/docs/specs/SPEC-019-op-service-account-agent-shell.md` §2.1: scope claim updated from "Trading only" to "Trading + Infra". Cross-ref S-46.
- `tieubao/trading/operations/broker-access.md`: add an `Infra` row to the "Service account + infra secret rotation" table.

## Verification checklist

- [ ] `op read op://Infra/cloudflare-api-token/credential` returns the token from a fresh Claude Code session (no scope denial).
- [ ] `op read op://Private/op-service-account-ops/credential` still returns scope denial (SA remains blind to its own storage).
- [ ] `tieubao/trading/operations/scripts/verify-op-trading-access.sh` exits 0 / 5 of 5 (no regression on trading-vault access).
- [ ] `wrangler deploy` from agent shell still works (CF token still loads via fish env; env-inherit path unchanged).
- [ ] SPEC-019 §2.1 + broker-access.md updated and committed in trading repo.
- [ ] `docs/sync-log.md` entry appended (hostname-tagged, per S-44).
- [ ] This doc's `status` flipped to `done`.

## Decisions made at planning time

1. **Final vault name**: `Infra` (terse, parallels existing `Private` + `Trading`). Candidates considered: `DeployOps`, `Agent-Infra`, `Shared-Infra`.
2. **vps-mon Telegram bot token + Discord webhook** (currently in `Trading`): **keep in `Trading`**, do not move to `Infra`. They alert on trading hosts; leak blast radius is trading-specific. Security-domain beats technical-layer per the S-46 heuristic.

## Rotation calendar

Next SA rotation: 2026-07-18 (90-day cycle from the S-42 rotation on 2026-04-19). Fold in any new Infra items discovered between now and then.
