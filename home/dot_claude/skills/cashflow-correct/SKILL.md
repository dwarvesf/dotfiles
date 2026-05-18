---
name: cashflow-correct
description: Use when the user wants to BULK edit historical rows in `tracking/ledger/transactions.csv` based on a filter criterion. Trigger phrases include "correct rows where [criterion]", "bulk update ledger", "fix attribution for [pattern]", "apply tag X to all rows matching", "all the [renovation/Min/etc.] rows in [period] should have [field=value]". NOT for single inline corrections to just-appended rows (cashflow-append handles those) or single-row historical edits (just edit the CSV directly with the user). Always shows a preview before mutating; always validates after; always commits atomically.
---

# Cashflow correct

Bulk-update historical rows in `tracking/ledger/transactions.csv`. Used for:
- Reclassifying a set of rows under a corrected category (e.g. all "Lượng" rows tagged with new `contractor-luong` tag)
- Adding property attribution to rows that lacked it ("all the rows mentioning P21608 should have property=Panoma")
- Fixing a wrong vocabulary value historically (e.g. wrong subcategory across many rows)
- Applying any cross-cutting transformation that touches multiple rows

## When to use

- User says: `correct rows where`, `bulk update ledger`, `fix attribution for`, `apply tag X to all`, `update all renovation rows`
- User identifies a pattern + a fix ("all rows where description contains 'Hada' should be Hado Centrosa")
- After a vocabulary change in `tracking/ledger/VOCABULARY.md`, propagate the change historically

## When NOT to use

- Single inline correction to just-appended row → `cashflow-append` (it has inline-correction logic)
- Adding new transactions → `cashflow-append`
- Querying / reports → `cashflow-report`
- Restructuring the schema (column add/rename) → that's a SPEC change + script change, not a correct skill

## Hard rules

1. **Always preview before mutating.** Show the user the count + a sample of matching rows. Get confirmation before writing.
2. **Preserve `id`.** IDs are stable identifiers; never change them in a correction.
3. **Append edit history to `notes`.** Format: `edited YYYY-MM-DD by hermes: <field> was X, now Y; reason: <user reason>`. If `notes` already has content, semicolon-separate.
4. **Atomic commit.** All rows touched in one correction are written in one file rewrite. If validation fails, revert ALL rows (not partial).
5. **Validate after rewrite.** Run `python infra/scripts/cashflow/validate_ledger.py`. Fail → revert from backup.
6. **Suggest regen.** After successful correction, suggest `python infra/scripts/cashflow/regenerate_monthly.py` for affected months (or `--all` if many months touched).
7. **Vocabulary discipline.** New value must be in `tracking/ledger/VOCABULARY.md` before being applied. If user proposes a new tag/category, ask to update VOCABULARY first.
8. **No silent merges.** If the correction would create duplicate IDs (shouldn't happen but check), abort and surface.

## Workflow

### Step 1: Parse the user's intent

Identify two parts:

| Part | Example |
|---|---|
| **Filter criterion** | "rows where description contains 'Lượng'", "all rows in 2025-08 with category=Home and property=''", "all `renovation` tagged rows" |
| **Change** | "add tag `contractor-luong`", "set property=TKH", "change category from Home to Renovation" |

If either is ambiguous, ask the user to clarify before loading the ledger.

### Step 2: Load + filter

```python
import csv
from pathlib import Path

ledger = Path("tracking/ledger/transactions.csv")
with ledger.open(newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

# Apply filter (example: description contains "Lượng")
matching = [r for r in rows if "Lượng" in r["description"]]
```

### Step 3: Show preview

Report to user:
- Count: "Found 8 rows matching."
- First 3 rows + last 2 rows as sample (date, amount, description)
- Proposed change: "Will add tag `contractor-luong` to each."

ASK: "Apply this change? (yes/no/show all)" — wait for explicit confirmation.

If user says "show all", dump all matching rows in a markdown table before the prompt.

### Step 4: Apply the change

For each matching row:

```python
today = date.today().isoformat()
for row in matching:
    # Apply the change. Example: add tag.
    tags = set(row["tags"].split("|")) if row["tags"] else set()
    tags.add("contractor-luong")
    row["tags"] = "|".join(sorted(tags))

    # Append edit history note
    note = f"edited {today} by hermes: added tag contractor-luong; reason: {user_reason}"
    row["notes"] = (row["notes"] + "; " + note) if row["notes"] else note
```

### Step 5: Backup + write

Before rewriting, save a backup of the current ledger:

```python
import shutil
backup_path = Path(f"tracking/ledger/transactions.csv.backup-{date.today().isoformat()}")
shutil.copy2(ledger, backup_path)
```

Then write the full file (header + all rows) atomically:

```python
# Write to temp file then rename — atomic on POSIX
tmp_path = ledger.with_suffix(".csv.tmp")
fieldnames = ["id", "date", "amount_vnd", "kind", "description",
              "category", "subcategory", "funding_source", "property", "tags",
              "source", "source_ref", "added_at", "added_by", "notes"]
with tmp_path.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames, quoting=csv.QUOTE_MINIMAL)
    writer.writeheader()
    for row in rows:
        writer.writerow(row)
tmp_path.replace(ledger)
```

### Step 6: Validate

Run `python infra/scripts/cashflow/validate_ledger.py`.

- **Pass:** Delete backup OR keep it (default keep — they're cheap and useful for audit). Continue.
- **Fail:** `shutil.copy2(backup_path, ledger)` to restore. Surface validation errors. Stop.

### Step 7: Suggest regen

Compute distinct months touched:
```python
months = sorted({r["date"][:7] for r in matching})
```

Suggest:
- If 1-2 months: `python infra/scripts/cashflow/regenerate_monthly.py YYYY-MM` for each
- If 3+ months: `python infra/scripts/cashflow/regenerate_monthly.py --all`

Don't auto-run; let the user decide. Keeps the correction commit and the regen commit separable.

### Step 8: Confirm to user

```
Updated ✓
  8 rows modified (added tag `contractor-luong`)
  Months affected: 2025-07, 2025-08, 2025-10
  Backup: tracking/ledger/transactions.csv.backup-2026-05-04
  Validation: passed (0 errors, 0 warnings)
  Suggested next: python infra/scripts/cashflow/regenerate_monthly.py --all
```

## Worked examples

### Example 1: add tag to a contractor's rows

User: `add tag contractor-luong to all rows where description contains "Lượng"`

Skill:
1. Filter: `"Lượng" in description` → 8 rows (all in Cải tạo TKH renovation context)
2. Preview: show count + sample
3. Confirm
4. For each: add `contractor-luong` to tags
5. Backup, write, validate (pass)
6. Suggest regen for 2025-07, 2025-08, 2025-10
7. Confirm

### Example 2: fix a misattribution propagated historically

User: `all rows mentioning P21608 should have property=Panoma`

Skill:
1. Filter: `"P21608" in description AND property != "Panoma"` → maybe 1 row currently (most are already correct from this session's fix)
2. Preview, confirm, apply, validate, regen suggestion.

### Example 3: VOCABULARY introduces new subcategory; propagate

User: `we just added "Coffee" as subcategory under Everyday — apply it to all Trang Credit Card rows where description contains "Highlands" or "Phuc Long" or "Starbucks"`

Skill:
1. Confirm "Coffee" is in VOCABULARY.md (read the file). If not: tell user to add it first; abort.
2. If yes: filter, preview, confirm, apply (`subcategory = "Coffee"`), validate, regen.

### Example 4: correct an entire category move

User: `change all "Renovation" category rows in 2025 with property=TKH to subcategory="TKH 2025 phase"`

Skill:
1. Filter: `category="Renovation" AND property="TKH" AND date startswith "2025"` → ~30 rows
2. Confirm "TKH 2025 phase" is acceptable (probably not in vocabulary; ASK user before applying).
3. If user wants it: ask them to add to VOCAB first, then apply.

## Anti-patterns

- ❌ **Apply without preview.** Always show count + sample first.
- ❌ **Partial state on validation fail.** All-or-nothing. Restore from backup.
- ❌ **Edit IDs.** Never. They're keys.
- ❌ **Forget to add edit history note.** Every edited row gets a note appended.
- ❌ **Use a category not in VOCABULARY.** Update vocabulary first.
- ❌ **Auto-regen markdown.** Suggest only; let user decide. Keeps git history clean (correction commit ≠ regen commit).
- ❌ **Run on a corrupted ledger.** If validation FAILS BEFORE applying changes, abort and surface — don't compound corruption.

## Edge cases

- **Bulk delete a row** (rare; transactions shouldn't be deleted, but if user genuinely wants to): treat as a separate "delete" mode. Show preview, require explicit "delete N rows? yes" confirmation, write a deleted-rows backup CSV alongside the regular backup.
- **Conflicting filters** (filter that matches 0 rows): report "0 matching rows; nothing to do."
- **Filter matches the whole ledger** (e.g. user typo'd a too-broad filter): if matching rows > 100, ASK twice to confirm. This is a guardrail against accidentally rewriting the whole ledger.
- **Edit a Hermes-appended row from cashflow-append**: works fine. The note will say "edited" alongside any prior history.

## Related skills

- `cashflow-append` — single inline transaction add + recent-row inline correction
- `cashflow-report` — query / reports
- `cashflow-close` — batch ingestion (e.g. a new bank statement) of MANY rows; uses different mechanics

## References

- SPEC-001: `docs/specs/SPEC-001-cashflow-ledger.md`
- Vocabulary: `tracking/ledger/VOCABULARY.md`
- Helper scripts: `infra/scripts/cashflow/`
- ADR 0015: `decisions/0015-cashflow-ledger-single-csv.md`
