---
name: agency-lead-radar
description: Run the monthly lead-gen sweep for Han's two-line services agency (AI Build, Ops Run). Sweeps job boards, classifies postings by service-line + region + signal strength, generates outreach drafts, tracks state across months. Use when the user says "monthly lead sweep", "who is hiring for the agency", "agency lead radar", "/lead-radar", "run the radar", "lead-gen for [month]", or asks to refresh leads.
---

# agency-lead-radar

Pipeline lives at `~/workspace/tieubao/ops-toolkit/experiments/agency-lead-radar/`. Spec is `SPEC.md`; config is `config.toml`. Implementation is Python under `code/` (TBD as of 2026-05-11; spec drafted, implementation deferred).

## Trigger phrases

- "monthly lead sweep" / "lead sweep" / "lead-radar" / "lead radar"
- "who is hiring for the agency"
- "refresh agency leads" / "get me May leads" / "get me [month] leads"
- "run the radar" / "rad radar" / `/lead-radar`

## Workflow (once implementation lands)

1. **Confirm scope.** Default = current month, all 8 regions, both lanes, top-30 drafts. Ask only if the user said something non-default.
2. **Check config.** Make sure `config.toml` has `agency.us_entity` and `outreach.sender_name` filled in. If still `TBD`, ask the user once before generating drafts (drafts will name the agency).
3. **Run.**
   ```
   cd ~/workspace/tieubao/ops-toolkit/experiments/agency-lead-radar
   uv run radar.py --month {YYYY-MM}
   ```
4. **Surface results inline:**
   - TL;DR (4-6 bullets)
   - Market scene table (per-region hiring volume + dominant signal)
   - Top 10 leads (AI + Ops combined, with diff-status flags from state)
   - Top 5 cross-cut leads
   - Path to full report
5. **Offer follow-ups:**
   - Regenerate outreach drafts with a different tone / length
   - Deep-dive a specific region or company
   - Mark a lead as `contacted` / `replied` / `meeting` / `dead` (updates `state.sqlite` via `radar.py state set --company-key <key> --status <s>`)
   - Show the diff vs last month

## Pre-implementation fallback (today)

The implementation isn't written yet. Until it lands, if the user invokes this skill:

1. Acknowledge the radar isn't implemented yet; point them at `experiments/agency-lead-radar/SPEC.md` for the design.
2. Offer to run the spec's pipeline manually via a one-off Agent dispatch (sweep HN + RemoteOK, classify with rules, drop a markdown report under `/tmp/`). This is the v0-by-hand pattern used on 2026-05-11.
3. Capture any new requirements that surface from the manual run as TODOs in the spec.

## State management

Cross-run state lives in `state.sqlite` next to the spec. Reports land at `reports/YYYY-MM/`. Both gitignored. Contains client names + drafts; never commit, never quote in public chats.

## Privacy

This experiment outputs target-company names, leadership hints, and pre-drafted outreach. Treat reports as confidential. Per ops-toolkit privacy rule: never paste lead-list rows into public til or Show-and-tell channels.

## Phasing

| Phase | Status | Scope |
| --- | --- | --- |
| v0 | not started | HN + RemoteOK, rule-based classify, LLM drafts top-30, markdown report |
| v1 | not started | + WWR + r/forhire + state.sqlite + market-scene aggregation |
| v2 | not started | LLM-assisted classify, diff-since-last-run |
| v3 | not started | Graduate to `tools/agency-lead-radar/` |

Graduate to `tools/` after 3 monthly runs + ≥1 closed deal traceable to a radar lead.
