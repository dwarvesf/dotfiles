---
name: local-ocr
description: Use when the user wants to OCR or extract fields from a sensitive household document (Vietnamese birth certificate, hộ khẩu, CCCD scan, hospital paper, lab PDF, signed contract) **without sending it to a cloud LLM**. Trigger phrases include "OCR this birth cert", "OCR <file>", "extract fields from <file>", "process this giấy khai sinh", "scan this for vault data", "structured extract <file>", "OCR locally", "use the local model on this", "process this document on the Mini", the **auto-absorb canonical phrase**: "**OCR and absorb <path> for <person>**" or "**process and apply <path> to <person>'s profile**" (triggers extract + auto-write to health/<person>.md + _vault/legal/notes.md + archive PDF; structured YAML returns to Claude session), and the **blind-absorb canonical phrase** (SPEC-006): "**blind-absorb <path> for <person>**" (same end-state, but the absorb-reasoning step runs locally on Qwen3.6:35b-a3b so no extracted field values reach Claude; user reviews via `git diff` before commit). Wraps the `local-ocr` CLI in `~/workspace/tieubao/ops-toolkit/tools/local-ocr/`. NOT for non-sensitive content where Apple Live Text or cloud Claude would do. NOT for inline-pasted images (already on Anthropic; skill must push back).
---

# local-ocr

OCR + structured field extraction for sensitive household documents via the local Ollama running on the Mac Mini. Zero cloud round-trip. Default DeepSeek-OCR for Vietnamese diacritic-rich text; Qwen3-VL fallback for complex layouts; Qwen 3.6 for schema-strict structured extraction.

## When to use

- User says: "OCR this birth cert", "OCR /path/to/file.pdf", "extract fields from giấy khai sinh", "structured extract this", "process the doc in `_inbox/`", "use the Mini OCR on this".
- User drops a file path to a Vietnamese ID-class doc in `_inbox/`, `_vault/legal/staging/`, or anywhere on disk.
- User wants the `safe_for_git:` / `vault_only:` schema split for a household doc going into family-office.

## When NOT to use

- User pastes an image **inline in chat** → see "Hard rule" below. Push back, do not call the CLI.
- User has clearly non-sensitive content (a public PDF, their own writing, a meme) → suggest cloud Claude or Apple Live Text instead; this is the heavier path.
- User wants to extract fields from a CSV, plain-text doc, or already-OCR'd text → use a different tool.
- Non-Vietnamese, non-ID-class doc and the schema split is meaningless → use plain `ocr` mode, not `structured`.

## Hard rule (load-bearing)

**If the user pastes an image directly into chat, do NOT proceed with OCR.** That image has already been uploaded to Anthropic's servers in your context window. Calling the local CLI on a now-also-on-Anthropic doc defeats the purpose of the local pipeline.

When this happens, push back clearly:

> The image you just pasted is already on Anthropic's side (it's in our conversation context). The local pipeline only buys you privacy if the file *never* leaves your machine. Save the image to disk (e.g. `_inbox/<name>.png`) and tell me the path; I'll OCR it on the Mini and you can delete this conversation afterwards if the doc was sensitive.

Do not silently proceed. The user needs to understand the leak path.

For **PDF in vault** (`_vault/legal/...`) the user references by path: that's fine, no chat upload; proceed.

## Endpoint and CLI

- CLI: `~/workspace/tieubao/ops-toolkit/tools/local-ocr/local_ocr.py`
- Endpoint: `http://100.118.23.42:11434` (the Mini's personal Tailnet identity; do NOT use `mac-mini-danang:11434` — that's the work-tagged identity and Ollama is bound to the personal one only)
- Override with the `OLLAMA_HOST_URL` env var when you're off-Tailnet or testing against a different box. Scheme is required (e.g. `http://192.0.2.1:11434`).
- Health check: `local-ocr health`

If `local-ocr health` fails, surface the error to the user. Do not retry blindly. Common causes: Mini offline, Tailscale down, agent unloaded (`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/mini.ollama.plist`), models pruned (`ollama list` on Mini).

## Workflow

### Mode A: Review mode (default, conservative)

User just says "OCR this", "structured extract this", or similar without naming a target person/profile.

1. Confirm the file path. If the user only described the doc without giving a path, ask where it is.
2. **If user pasted inline image**, apply the hard rule above. Stop.
3. Run health check first:
   ```bash
   ~/workspace/tieubao/ops-toolkit/tools/local-ocr/local_ocr.py health
   ```
4. Run structured extraction:
   ```bash
   ~/workspace/tieubao/ops-toolkit/tools/local-ocr/local_ocr.py structured <path>
   ```
5. Show the user the two YAML blocks. Highlight in summary text:
   - **safe_for_git fields** — what would land in family-office markdown
   - **vault_only fields** — what would NEVER touch git, must go to `_vault/legal/notes.md` or equivalent
6. Ask the user to confirm before any commit. **Never auto-commit fields from `vault_only:`**.

### Mode B: Auto-absorb mode (explicit trust)

Triggered by the canonical phrase:

> "OCR and absorb `<path>` for `<person>`"
> "process and apply `<path>` to `<person>`'s profile"
> "absorb `<path>` into `<person>`"

When this phrase is used, run the full pipeline AND apply the writes without per-field confirmation. The user explicitly opted in by saying "absorb / apply" + naming a destination person; per-step confirmation would be friction without benefit.

1. Resolve `<person>` to a profile file (e.g. `health/<person>.md`). If ambiguous, ask once before running the rest.
2. **If user pasted inline image**, apply the hard rule. Stop.
3. Run `local-ocr health` (sanity).
4. Run `local-ocr structured <path>` (CLI auto-detects `doc_class`). Capture output.
5. Apply the writes per the **per-class destination table** below.
6. Print a summary: detected `doc_class`, source file → archived path, profile diff, vault diff, PII-verify status. No prompts.
7. **One exception to "no prompts"**: if Presidio flags a finding above score 0.7 in `safe_for_git`, STOP, show the warning, ask the user to confirm before continuing. That's the only blocking gate.

### Per-class destination table (Mode B)

The CLI emits `doc_class:` as the first field of the YAML. Route based on it. Each class lists the (a) safe-fields destination, (b) vault-fields destination, (c) PDF archive slug.

| `doc_class` | safe_for_git fields land in | vault_only fields land in | Archive PDF as |
|-------------|------------------------------|---------------------------|----------------|
| `birth-cert` | `health/<person>.md` → `## Snapshot` + `## Encounters` (birth admission) | `_vault/legal/notes.md` § new dated section | `_vault/legal/birth-cert-<person>-<dob>.pdf` |
| `cccd` | `health/<person>.md` → `## Snapshot` (add "Government ID" row with issue + expiry; do NOT include the number) | `_vault/legal/notes.md` (full CCCD number, hộ khẩu address) | `_vault/legal/cccd-<person>-<issue-date>.pdf` |
| `cmnd` | Same as `cccd` | Same as `cccd` | `_vault/legal/cmnd-<person>-<issue-date>.pdf` |
| `ho-khau` | (no health/<person>.md writes — sensitive overall; optional cross-link in `docs/account-registry.md`) | `_vault/legal/notes.md` (head of household + full address + all members) | `_vault/legal/ho-khau-<household-slug>-<issue-date>.pdf` |
| `red-book` | `assets/real-estate.md` (locality, area, type, issue date — add or update the property row) | `_vault/legal/notes.md` (parcel ID, owner CCCD, full address, co-owners) | `_vault/legal/red-book-<property-slug>-<issue-date>.pdf` |
| `passport` | `health/<person>.md` → `## Snapshot` "Passport" row (type, country, expiry, vault path); ALSO `planning/<country>-migration.md` if migration plan exists for that country | `_vault/legal/notes.md` (passport_number, MRZ) | `_vault/legal/passport-<person>-<expiry>.pdf` |
| `visa` | `planning/<country>-migration.md` (timeline row: class, valid window, conditions) | `_vault/legal/notes.md` (visa_number, application_id, sponsor info) | `_vault/legal/visa-<person>-<class>-<valid-to>.pdf` |
| `bhyt` | `assets/insurance.md` (add or update the policy row); cross-link from `health/<person>.md ## Insurance` | `_vault/legal/notes.md` (card_number, registered clinic) | `_vault/legal/bhyt-<person>-<valid-to>.pdf` |
| `lab-result` | `health/<person>.md` → `## Metrics` (per-metric subsections; append new dated rows) | `_vault/legal/notes.md` (patient_id; cross-reference PDF for full panel) | `_vault/legal/lab-<person>-<test-date>.pdf` |
| `prescription` | `health/<person>.md` → `## Prescriptions log` (append rows); also update `## Medications` summary for active drugs | `_vault/legal/notes.md` (prescription_number, patient_id) | `_vault/legal/rx-<person>-<prescription-date>.pdf` |
| `imaging` | `health/<person>.md` → `## Imaging / procedures` (one line: date, modality, body part, plain-language finding, vault path) | `_vault/legal/notes.md` (accession_number, full radiology narrative) | `_vault/legal/imaging-<person>-<modality>-<study-date>.pdf` |
| `discharge` | `health/<person>.md` → `## Encounters` (new dated block) | `_vault/legal/notes.md` (patient_id, full discharge narrative, meds at discharge) | `_vault/legal/discharge-<person>-<discharge-date>.pdf` |
| `vaccination` | `health/<person>.md` → `## Vaccinations` (flip Status: due → done for each matching dose; add row if no scheduled match exists) | `_vault/legal/notes.md` (patient_id if present) | `_vault/legal/vax-<person>-<latest-dose-date>.pdf` |
| `other` | (manual review only; do not auto-write) | (manual review only) | `_vault/legal/<original-name>` (preserve original filename) |

**Note on `portrait`**: the `structured` CLI does NOT emit `doc_class: portrait` — it's not in the `--doc-class` choices and has no schema. Portraits are recognized only by `triage` (see Other subcommands below), which routes them to `_vault/legal/portrait-<person>-<date>.<ext>` without any field extraction. If a user drops a portrait into Mode B, the CLI will classify it as `other` and you'll fall through to the manual-review row.

### When `doc_class: other` is returned

Switch to Mode A behavior automatically: show the OCR text + the model's free-form `notes`, archive the PDF to vault, and ask the user where to land the content. No auto-writes.

### When `doc_class` doesn't match what you'd have expected

Sometimes the model misclassifies a doc (e.g. flags a discharge note as `medical-record` family which we group under `discharge`, or a Singapore EP letter as `other` because we didn't include "EP letter" in training). The user can re-run with `--doc-class <correct-name>` to force the right schema. Mention this option in Mode A output so the user has an obvious recovery path.

### Mode D: Blind absorb (SPEC-006; no field values reach Claude)

Triggered by the canonical phrase:

> "blind-absorb `<path>` for `<person>`"
> "blind-process `<path>` for `<person>`"
> "absorb `<path>` for `<person>` --blind" (flag form for explicitness)

**What it does:** runs the SAME pipeline as Mode B, but the absorb-reasoning step (which markdown sections to touch, what to write where) runs ENTIRELY on Qwen3.6:35b-a3b on the Mini. The CLI returns only a redacted summary to this Claude session: paths touched, line counts, run_id, archive path, audit path. The actual extracted field values never enter your conversation context. The user reviews via `git diff` in their terminal (NOT through you).

**When to pick this over Mode B:** the doc has high-sensitivity PII (full CCCDs, ID numbers, signatures, residences, third-party data) AND the user wants the strict invariant that no field values pass through Anthropic.

**Trade-offs vs Mode B:**
- Slower (~40s additional for the absorb-reasoning step).
- Slightly less polished output on judgment-call enrichments (e.g. follow-up TODO checkboxes); SPEC-006 §"Validation" tracks the quality delta per doc class.
- Only available for `birth-cert` in v1; other classes need `--force-class` until validated.

**Workflow:**

1. **If user pasted inline image**, apply the hard rule above. Stop.
2. Resolve `<person>` to a profile (e.g. health/danny.md exists; if not, ask).
3. Confirm the file exists at `<path>`. If the path is in `_inbox/`, that's normal.
4. Run the CLI with `--repo` pointing at the family-office repo root:
   ```bash
   ~/workspace/tieubao/ops-toolkit/tools/local-ocr/local_ocr.py absorb \
       --person <person> \
       --repo <family-office-root> \
       <path>
   ```
   Optional flags: `--dry-run` (writes only to `_vault/staging/`, not working tree), `--doc-class <name>` (skip auto-detect), `--force-class` (bypass class promotion gate).
5. Show the BLIND_ABSORB_RESULT v1 block VERBATIM to the user. Do NOT add commentary that paraphrases what changed (you don't know the values).
6. Tell the user the next step: `cd <family-office> && git diff` to review, then `git add -p` and commit (suggested commit message is in the manifest's `commit.suggested_message`, retrievable via `python3 -c "import json; print(json.load(open('<audit-path>'))['commit']['suggested_message'])"` if needed). If the user wants to back out, `local-ocr rollback <RUN-ID> --repo <family-office-root>`.

**Hard rule (additional, load-bearing):**

You MUST NOT read the values file at `_vault/audit/blind-absorb/RUN-<id>.values.json`. It contains the field values; reading it pulls them into your context and defeats the entire blind-absorb purpose. The PreToolUse hook on `_vault/legal/` MAY also cover this path; if a future hook doesn't, treat the no-read rule as binding regardless.

You also MUST NOT auto-invoke the structured YAML output for the same file via `local-ocr structured` after a successful blind absorb. The user opted into blind mode specifically; running the non-blind pipeline against the same source defeats it.

**Rollback:**

> "rollback blind-absorb run `<RUN-ID>`"
> "undo blind-absorb `<RUN-ID>`"

Calls `local-ocr rollback <RUN-ID> --repo <family-office-root>`. The CLI reads the manifest, verifies hashes haven't drifted (or `--force` if user accepts overwriting hand-edits), restores files from `_vault/staging/RUN-<id>/.backups/`, moves the PDF back to the original `_inbox/` path, and writes a `.rollback.json` sibling. Surfaces a structured `BLIND_ABSORB_ROLLBACK v1` block. Same redaction rules.

**Deeper reference:** the full Mode D usage guide (workflow, vault layout, failure statuses, audit subcommand) lives at `~/workspace/tieubao/ops-toolkit/tools/local-ocr/USAGE-blind-absorb.md`. Point the user there when they want more detail than this skill section.

### Mode C: Plain OCR (no schema split)

### Plain OCR (no schema split, when document type doesn't match the schema)

```bash
~/workspace/tieubao/ops-toolkit/tools/local-ocr/local_ocr.py ocr <path>
```

Default model is DeepSeek-OCR. For complex layouts, noisy scans, or when DeepSeek struggles:

```bash
~/workspace/tieubao/ops-toolkit/tools/local-ocr/local_ocr.py ocr <path> --model qwen3-vl
```

For DeepSeek with bounding boxes + region tags (visual audit trail):

```bash
~/workspace/tieubao/ops-toolkit/tools/local-ocr/local_ocr.py ocr <path> --mode grounded
```

### Side-by-side comparison (when in doubt)

```bash
~/workspace/tieubao/ops-toolkit/tools/local-ocr/local_ocr.py compare <path>
```

Useful when DeepSeek's output looks suspicious or the user wants a second opinion before committing field values.

### Other subcommands (housekeeping)

These verbs sit alongside `ocr` / `structured` / `compare` / `absorb` / `rollback`. Use them when the user's intent matches.

| User intent | Subcommand | Notes |
|---|---|---|
| "what's in this folder?" / "triage the inbox" / "what doc class is this?" | `local-ocr triage <dir-or-file> [--format json]` | Filename + extension heuristics only. No content reads, so it's safe to run against an `_inbox/` you haven't reviewed yet. Returns one row per file with sensitivity score + suggested doc-class hint (the hint set is broader than `structured`'s `--doc-class` choices: it recognises `portrait`, `bao-hiem-y-te`, `vaccine`, etc. as routing aliases). |
| "double-check this YAML for PII leaks" / "re-verify the extraction" | `local-ocr verify <yaml-file>` (or `-` for stdin) | Runs Presidio over the YAML and flags `safe_for_git` fields that look like PII. Same threshold as Mode B's blocking gate (0.7). Useful if a user hand-edited an extraction and you want a sanity pass before they commit. |
| "show me past blind-absorb runs" / "what did I absorb last week?" | `local-ocr audit list` | Lists every run in `_vault/audit/blind-absorb/`, newest first, redacted. |
| "show me run X's manifest" / "what files did blind-absorb touch on RUN-Y?" | `local-ocr audit show <run-id> [--format json]` | Prints the manifest for one run. Redacted by default. **Never invoke with `--full`** — the CLI's own help string warns "DANGER: reads .values.json and prints extracted field values. Do NOT use from an LLM session; only in your own terminal." That's the same load-bearing invariant as Mode D's no-read rule. |

None of these need the member-tier model or the 1Password key; they're local-only metadata/filename operations.

## Output format and human review

The CLI emits text by default; pass `--format json` for piping. For the structured pipeline, the YAML output looks like:

```yaml
safe_for_git:
  full_name: ...
  dob: YYYY-MM-DD
  sex: m | f
  place_of_birth: ...
  issuing_authority: ...
  issue_date: YYYY-MM-DD

vault_only:
  cccd_father: ...
  cccd_mother: ...
  ho_khau_address_full: ...
  registration_number: ...
  third_party_pii: []
```

After the model emits this, **human review is the load-bearing security control**. The skill should:

1. Render the YAML to the user clearly, separating the two blocks visually.
2. Flag anything that looks borderline (e.g. a `place_of_birth` that includes a hospital name might be too specific; suggest coarsening).
3. Ask the user to apply the split: "want me to write `safe_for_git` fields into `health/<kid>.md` and `vault_only` into `_vault/legal/notes.md`?"
4. Wait for explicit yes before any file write.

Never auto-write `vault_only` content to anywhere git-tracked. If unsure whether a path is git-tracked, run `git check-ignore <path>` from the repo root; non-zero exit means it IS git-tracked.

## Vault-side notes file

If `_vault/legal/notes.md` doesn't exist yet on this machine, create it with this header before appending sensitive fields:

```markdown
# Legal documents — vault-only notes

This file lives in `_vault/legal/` (iCloud-only, gitignored). It holds sensitive
fields extracted from household legal documents (CCCD numbers, hộ khẩu addresses,
registration numbers, third-party PII) that MUST NEVER touch git.

## Conventions
- One section per source document, dated `YYYY-MM-DD-<short-slug>`.
- Reference the original PDF/image by path: `_vault/legal/<filename>`.
- Cross-link from the markdown profile in family-office (e.g. `health/min.md`)
  by path, never by inlining the values.
```

Append entries newest first, structured per document. Each entry should reference back to the corresponding `health/<person>.md` or wherever the safe fields landed.

## Trigger phrases (priority order)

If the user is unambiguous, proceed. If two skills could match, prefer this one when:

- The doc is Vietnamese
- The doc is ID-class or contains PII (birth cert, hộ khẩu, CCCD, lab report, hospital paper)
- The user said "local", "Mini", "on-device", "private", "sensitive", "don't send to cloud"

Defer to other skills when:

- It's a `.docx` or contract being drafted (use `vn-contract-format` for that)
- It's a transaction log / receipt for cashflow ingest (use `cashflow-close`)
- It's general inbox triage with no PII (use `ingest-to-wiki`)

## Failure modes to watch for

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| `local-ocr health` exit 1 with "unreachable" | Mini offline or Tailscale down | Check `tailscale status`; ssh into Mini to verify |
| Health passes but `ocr` returns "If you have any questions..." | DeepSeek-OCR with wrong prompt — should not happen via this CLI but flag if it does | Verify CLI is current; re-pull `deepseek-ocr:3b` if model file corrupt |
| `structured` produces empty `safe_for_git:` and `vault_only:` blocks | Qwen 3.6 schema step misfired | Run `ocr` mode standalone to verify OCR worked, then debug the structured prompt |
| Response says model not loaded | Model unloaded due to memory pressure | Ollama auto-loads on next call; just retry |

## References

- Tool: `~/workspace/tieubao/ops-toolkit/tools/local-ocr/`
- SPEC: `~/workspace/tieubao/ops-toolkit/tools/local-ocr/SPEC.md`
- Driving research: `tieubao/family-office/docs/research/local-model-for-sensitive-docs.md`
- Memory: `~/.claude/projects/-Users-tieubao-workspace-tieubao-family-office/memory/reference_mini_ollama_deployment.md`
- Schema source: `tieubao/family-office/health/README.md` (privacy split)
