---
id: S-52
title: Secrets architecture synthesis doc (the map above the spec chain)
type: docs
status: done
date: 2026-05-07
---

# S-52: Secrets architecture synthesis doc

## Problem

The dotfiles repo's secrets / keys / credentials surface has accumulated 13
specs over the past several months. Each one closes a slice. Read in
isolation, each is good. Read together, they form a fragmented mosaic that
nobody (including future-author) can hold in their head.

Today's reader entry-points are:

- `docs/1password.md` (single-machine model)
- `docs/1password-multi-machine.md` (multi-machine extension)
- The S-XX spec chain (incremental decisions)
- `docs/decisions/` (macro ADRs)
- Scattered references in CLAUDE.md, README

That gives a forker:

- A pattern that works for the daily case
- A spec chain that records HOW we got here
- **No single map of the whole problem space**, no roadmap, no catalog of
  open questions

What's missing is a doc that sits *above* the spec chain. Not a spec (specs
are about specific changes). Not a runbook (runbooks are about specific
procedures). Not a how-to (`1password.md` is the how-to). A **map**: the
credential × device × path matrix, the threat model, the spec-to-slice index,
and the open-questions catalog.

The trigger to write it now: [S-51](S-51-multi-machine-sa-access.md) just
shipped, consolidating the multi-machine slice. The pattern is fresh, the
discipline rule is codified, and the next several "what should we work on?"
conversations will benefit from a settled map.

## Solution

A single synthesis doc at `docs/secrets-architecture.md` that covers:

1. **Why this doc exists** — meta-doc, not a spec, not a runbook
2. **Threat model** — adversaries, what's protected by what
3. **Credential taxonomy** — what types of secrets/keys live in this repo's surface
4. **Device taxonomy** — primary, secondary, iOS, future-Linux, hardware wallet
5. **The credential paths** — generalized version of the 4 paths from S-51, plus future paths
6. **Spec-to-slice mapping** — which spec closes which slice
7. **Open questions / catalog** — explicit, status-tagged, with next-step pointers
8. **When to commission a new spec vs an operations cookbook** — decision tree
9. **Related** — cross-links to specs, decisions, how-to docs

Acceptance criteria:

- [x] Doc exists at `docs/secrets-architecture.md`
- [x] Every existing secrets-related spec (S-09, S-16, S-33, S-35, S-38,
      S-42, S-43, S-45, S-46, S-47, S-48, S-49, S-51) appears in the
      spec-to-slice table with a one-line summary and current status
- [x] At least 6 open questions are catalogued with status, blocker, next-step
- [x] Threat model section names at least 4 distinct adversary scenarios
- [x] Credential taxonomy distinguishes at least 6 credential classes
- [x] Device taxonomy covers GUI primary, SSH-driven secondary, iOS SSH
      client, hardware wallet, and explicitly flags Linux secondary as open
- [x] Doc passes `scripts/test-doc-discipline.sh` (placeholder-clean,
      framework artifact)
- [x] `docs/1password.md`, `docs/1password-multi-machine.md`, and `README.md`
      link to the synthesis doc as the entry point for the secrets surface
- [x] `docs/operations/2026-05-mini-sa-seed.md` is referenced as an example
      of the framework-vs-cookbook split

## Trade-offs accepted

| Trade-off | Rationale |
|---|---|
| One more file to keep updated | The synthesis doc is meant to evolve with the spec chain. Each new spec lands → update spec-to-slice table + close/open questions in the catalog. Same churn pattern as `tasks.md` or `sync-log.md`. |
| Duplication risk with `1password.md` and `1password-multi-machine.md` | Synthesis doc is a *map*, not a *manual*. It points at the manuals; it does not copy them. Section-level discipline: synthesis doc says "see X for details" rather than restating. |
| Some open questions are subjective ("is this worth doing?") | That's the point. The catalog forces the prioritization conversation rather than burying it in scattered TODOs. |

## Non-goals

- Replacing `docs/1password.md` or `docs/1password-multi-machine.md`. Those
  remain the day-to-day manuals; the synthesis doc points at them.
- Designing solutions to any open question. Open questions are catalogued,
  not designed. Each becomes a future spec when commissioned.
- Becoming a personal cookbook. The synthesis doc is a framework artifact;
  it must pass `scripts/test-doc-discipline.sh`.
- Codifying the prioritization order for open questions. The catalog has
  status (open / partially-designed / blocked-on-X) but does not pick the
  next slice to work. That's a per-session decision.
- Bundling SSH agent forwarding tutorials, keychain-fu, age commands, etc.
  This doc maps where those live; the docs themselves stay where they are.

## Files changed

**New:**
- `docs/specs/S-52-secrets-architecture-synthesis-doc.md` (this spec)
- `docs/secrets-architecture.md` (the synthesis doc)

**Modified:**
- `scripts/test-doc-discipline.sh`: add `docs/secrets-architecture.md` to
  the FRAMEWORK_DOCS list so the discipline test covers it.
- `docs/1password.md`: add a one-line pointer to the synthesis doc near
  the top, and to the "See also" / spec chain area.
- `docs/1password-multi-machine.md`: add the synthesis doc to its "See also"
  list.
- `README.md`: add the synthesis doc to the Docs table as the
  whole-secrets-surface entry point.
- `docs/tasks.md`: append S-52 to the completed list.
- `docs/sync-log.md`: hostname-tagged entry on landing.

**Not changed:**
- The spec chain itself. Existing S-XX specs are untouched.
- The framework code (`secrets.fish.tmpl`, `dotfiles.fish`, `secret-cache-read`).
- The author's operations cookbook (`docs/operations/2026-05-mini-sa-seed.md`).

## Testing

```fish
# 1. Discipline test passes (synthesis doc is placeholder-clean).
./scripts/test-doc-discipline.sh
# expect: ✓ Doc discipline contract holds.

# 2. Synthesis doc references every secrets-related spec by ID.
for spec_id in S-09 S-16 S-33 S-35 S-38 S-42 S-43 S-45 S-46 S-47 S-48 S-49 S-51
    if not grep -q $spec_id docs/secrets-architecture.md
        echo "✗ Synthesis doc missing reference to $spec_id"
        exit 1
    end
end
echo "✓ All 13 secrets-related specs referenced."

# 3. Synthesis doc links to the existing manuals.
for ref in 1password.md 1password-multi-machine.md operations/2026-05-mini-sa-seed.md
    if not grep -q $ref docs/secrets-architecture.md
        echo "✗ Synthesis doc missing cross-link to $ref"
        exit 1
    end
end
echo "✓ All cross-references present."

# 4. README and the two manuals link back to the synthesis doc.
for src in README.md docs/1password.md docs/1password-multi-machine.md
    if not grep -q "secrets-architecture.md" $src
        echo "✗ $src is missing the synthesis-doc back-link"
        exit 1
    end
end
echo "✓ Back-links present."
```

All four checks must pass before flipping `status: done`.

## Spec chain

| Spec | What | Status |
|---|---|---|
| [S-09](S-09-age-encryption.md) | Age encryption for chezmoi-managed files | done |
| [S-16](S-16-age-encryption-guided-setup.md) | Age encryption guided setup | done |
| [S-33](S-33-bitwarden-secrets.md) | Bitwarden secrets backend (alternative) | planned |
| [S-35](S-35-local-pattern-and-lazy-secrets.md) | Lazy resolution + Keychain cache | done |
| [S-38](S-38-ssh-key-backup.md) | SSH key inventory, adoption, offline backup | done |
| [S-42](S-42-service-account-agent-auth.md) | SA auto-load for agents | superseded by S-47 |
| [S-43](S-43-sync-secret-cache-visibility.md) | Surface registered-but-uncached secrets | done |
| [S-45](S-45-secret-refresh-no-echo.md) | Stop echoing secret values | done |
| [S-46](S-46-three-vault-model-for-agent-infra-secrets.md) | Multi-vault tiering | proposed |
| [S-47](S-47-agent-token-opt-in-wrapper.md) | Opt-in wrapper | amended by S-49 |
| [S-48](S-48-secret-add-narrow-apply-scope.md) | Narrow chezmoi apply scope | done |
| [S-49](S-49-dual-mode-op-via-fish-interceptor.md) | Dual-mode op interceptor | done |
| [S-51](S-51-multi-machine-sa-access.md) | Multi-machine extension | done |
| **S-52** | **Synthesis doc (this spec)** | **done** |

S-52 is meta-work; it does not depend on S-46 or any other proposed slice.
The synthesis doc will get updated as future specs land; the spec entry
itself stays `done` once shipped.
