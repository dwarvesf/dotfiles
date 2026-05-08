---
id: S-59
title: Sync `# Machines I work from` table with ops-toolkit SPEC-001 / SPEC-002 / ADR-0020
type: docs
status: done
date: 2026-05-09
---

# S-59: Sync `# Machines I work from` table with ops-toolkit canonical updates

## Problem

The `# Machines I work from` table inside `home/dot_claude/modify_CLAUDE.md.tmpl`
was last updated when the canonical machine map lived in `dfoundation`. Since
then, three load-bearing updates landed in `tieubao/ops-toolkit` and have not
flowed back into dotfiles:

1. **Mini Tailscale hostname.** SPEC-002 (Mobile pilot, shipped 2026-05-07)
   ratifies `mac-mini-danang` as the canonical Tailscale FQDN. Current
   dotfiles text says `ssh mini` (Tailscale) / `ssh mini-lan` (mDNS); the
   Tailscale form is right but the hostname is the FQDN, not just `mini`.
2. **Daemon namespace split.** dfoundation ADR-0020 +
   `SPEC-054-partial-reversal-tenant-artifacts-back.md` (both 2026-05-06,
   refined 2026-05-08) renamed personal-Mini daemons from
   `system/foundation.d.*` to `mini.*` (e.g. `mini.restic-backup`,
   `mini.upgrade-check`) and moved their plists from `dfoundation/infra/
   substrate/mac-mini/` into `ops-toolkit/tools/{mac-mini-substrate,
   mac-backup}/`. The `foundation.d.*` namespace is now reserved strictly
   for Dwarves-tenant LaunchDaemons (`foundation.d.hermes-*`,
   `foundation.d.ollama`). The current dotfiles text mixes both under
   `foundation.d.*`.
3. **Mobile pilot path.** SPEC-002 documents iPhone -> Termius + Mosh +
   Tailscale -> `tieubao@mac-mini-danang` as Phase 1 of the mobile pilot.
   No mention of mobile pilot in dotfiles today.

Plus a related drift: SPEC-041 / SPEC-054 moved the personal-Mini substrate
specs out of `dfoundation/infra/substrate/mac-mini/` into
`ops-toolkit/tools/mac-mini-substrate/` and `ops-toolkit/tools/mac-backup/`.
The current dotfiles text points only at dfoundation; ops-toolkit deserves
a callout.

The cost of the drift: when a Claude Code session lands on a fresh machine
or in an unrelated repo, the `# Machines I work from` context is the
first thing it reads. Wrong hostname = wrong SSH target. Wrong daemon
namespace = wrong `launchctl print` invocation. Missing mobile path =
LLM does not know iPhone is in the loop.

## Solution

Update the `# Machines I work from` section in
`home/dot_claude/modify_CLAUDE.md.tmpl` heredoc (the dotfiles canonical,
post-S-56). Specifically:

### Table updates

| Cell | Current | New |
|---|---|---|
| Mini SSH alias | `ssh mini` (Tailscale) / `ssh mini-lan` (mDNS) | `ssh mac-mini-danang` (Tailscale FQDN, primary) / `ssh mini-lan` (mDNS fallback) |
| Mini role text | "the one ADR-0012 grant: kickstart -k system/foundation.d.hermes-agent" | unchanged for the Hermes-tenant grant; add separate sentence on `mini.*` for personal daemons |
| mini-tieubao role text | "broader launchctl verbs ... against system/foundation.d.*" | clarify: foundation.d.* is Dwarves tenant; mini.* is personal (restic backup, upgrade-check); SPEC-052 grants cover both namespaces |

### New rows

Add a row for the iPhone mobile pilot (SPEC-002):

```
| iphone (mobile pilot) | Termius + Mosh -> Tailscale -> tieubao@mac-mini-danang | tieubao | iOS pilot path. Tasks needing MCP / op:// / Hermes verbs run here via mosh; stateless parallel work runs in the iOS Claude app's Cloud Sandbox. Phase 1 of SPEC-002; no new daemons. |
```

### Trailing prose updates

Replace:

> The Mini hosts the ops-agent (`foundation.d.hermes-agent` LaunchDaemon,
> project at `/Users/server/dev/hermes-agent`) plus Ollama and
> `vps-mon-agent`. SPEC-032 specifies the substrate; ADR 0012 explains why
> `server`'s grant is narrow.

with (no em dashes):

> The Mini runs two daemon namespaces. `foundation.d.*` are
> Dwarves-tenant daemons (`foundation.d.hermes-agent`,
> `foundation.d.hermes-insights-daily`, `foundation.d.ollama`); SPEC-032
> in dfoundation specifies the substrate; ADR-0012 explains why server's
> grant is narrow. `mini.*` are personal daemons (`mini.restic-backup`,
> `mini.restic-check`, `mini.upgrade-check`) per ADR-0020 / SPEC-054 in
> ops-toolkit; the substrate spec lives at
> `ops-toolkit/tools/mac-mini-substrate/`. Both namespaces respond to
> `launchctl print system/<label>` from `tieubao@` per SPEC-052. The
> `vps-mon-agent` is in `ops-toolkit/tools/vps-mon/`.

## Test

1. **Render check.** `chezmoi execute-template < home/dot_claude/modify_CLAUDE.md.tmpl` succeeds; output contains the updated table cells, the new iphone row, and the rewritten prose.
2. **Idempotency (S-55 regression).** Apply twice; line count stable. (Pre-S-59 stable count was 246 on Mac mini; post-S-59 will be a new stable count.)
3. **Live deployment.** `chezmoi apply ~/.claude/CLAUDE.md` deploys cleanly; live file contains the new content.
4. **Cross-reference integrity.** Spec references mentioned in the new prose all resolve to actual files in their owning repos:
   - `dfoundation/docs/decisions/0012-claude-code-narrow-sudo.md`
   - `dfoundation/docs/decisions/0020-tenant-coupled-artifacts-stay-with-tenant.md`
   - `dfoundation/docs/specs/infra/SPEC-032-mac-mini-infrastructure-substrate.md`
   - `dfoundation/docs/specs/infra/SPEC-052-ops-script-ssh-alias-convention.md`
   - `dfoundation/docs/specs/infra/SPEC-054-partial-reversal-tenant-artifacts-back.md`
   - `ops-toolkit/_meta/SPEC-001-topology-v0.md` and `SPEC-002-mobile-pilot-v0.md`
   - `ops-toolkit/tools/mac-mini-substrate/` and `ops-toolkit/tools/mac-backup/`
5. **Em-dash hygiene.** `grep -c '—' home/dot_claude/modify_CLAUDE.md.tmpl` returns 0 in the changed region (per global rule).

## Out of scope

- **Auto-syncing the machine table from ops-toolkit.** This is a one-shot
  hand-update. A future spec could automate via a chezmoi-template-time
  fetch from ops-toolkit, but the table changes maybe twice a year.
- **Adding Phase 2 / Phase 3 mobile pilot infrastructure.** SPEC-002
  documents the escalation paths but Phase 1 is what is shipped. Dotfiles
  should reflect Phase 1 only.
- **Restructuring the table format.** Keep the same 4-column shape so
  diffs are minimal.

## Definition of done (per S-44)

- [x] Spec frontmatter `status: done`
- [x] Tick in `docs/tasks.md`
- [x] Hostname-tagged entry in `docs/sync-log.md`
- [x] Test 1, 2, 3 pass on Mac mini; test 5 returns 0
