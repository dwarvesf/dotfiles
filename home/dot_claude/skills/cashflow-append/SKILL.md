---
name: cashflow-append
description: Use when the user wants to log a single transaction to the family-office cashflow ledger via natural language. Trigger phrases include "add expense", "log [amount] [merchant]", "paid [X] for [Y]", "Trang got [amount] from [source]", "Bảo gave me [amount]", or any inline natural-language transaction (e.g. "200K coffee at Highlands today, paid by card"). Also handles in-flight corrections like "fix that last one to category X" or "wait, the amount was 250K not 200K". Appends a row to `tracking/ledger/transactions.csv` per the schema in SPEC-001 and the contract in `tracking/ledger/README.md`. NOT for batch ingestion of screenshots / CSVs (use cashflow-close) or bulk historical edits (use cashflow-correct).
---

# Cashflow append

Append a single transaction to the household ledger from natural-language input. Implements the Hermes interface contract documented at `tracking/ledger/README.md`.

## When to use

- User describes a single transaction in chat: "200K coffee at Highlands today, paid by card"
- User says: `add expense`, `log [amount]`, `paid [X] for [Y]`, `Trang got paid`, `Bảo ck [amount]`
- User wants to immediately correct a transaction just logged: "fix that last one to category X", "the amount was wrong"
- User is in a Telegram-Hermes session and sends a transaction message

## When NOT to use

- User drops screenshots / bank CSVs / receipts in `_inbox/` and wants batch processing → use `cashflow-close`
- User wants to bulk-edit historical rows ("apply tag X to all 2025-08 renovation rows") → use `cashflow-correct`
- User wants to query / report ("what did we spend on Min in Q3?") → use `cashflow-report`
- User wants to add a new vocabulary term → ask explicitly to update `tracking/ledger/VOCABULARY.md` first

## Hard rules

These are non-negotiable. Violating any of them produces a corrupt ledger.

1. **Schema is binding.** Every appended row must match `docs/specs/SPEC-001-cashflow-ledger.md` § Schema (15 columns, exact column order, header row already present). Validate via `infra/scripts/cashflow/validate_ledger.py` after every append.
2. **Append-only.** Add the row at the END of the CSV. Never insert mid-file. Never reorder existing rows.
3. **Positive amount, sign from kind.** `amount_vnd` is always a positive integer. Sign is implied by `kind` (expense subtracts, income adds, transfer is balance-neutral, refund offsets).
4. **Vocabulary discipline.** Use only values listed in `tracking/ledger/VOCABULARY.md` for `category`, `subcategory`, `funding_source`, `property`, and standard `tags`. New tags allowed but should be added to VOCABULARY in the same session if used. Never invent categories silently.
5. **Validate after every append.** Run `python infra/scripts/cashflow/validate_ledger.py`. If it fails, **revert the append** (delete the line you added) and surface the validation errors to the user. Do not commit a failed-validation state.
6. **Vietnamese diacritics preserved.** `description` field keeps full Vietnamese text verbatim. Do NOT strip diacritics.
7. **Empty fields are empty strings.** Never write `null`, `none`, `N/A`, or `-`. Use the empty string `""`.
8. **No emoji in vocabulary fields.** `category`, `subcategory`, `funding_source`, `property`, `tags` are emoji-stripped. Emoji are fine in `description` and `notes`.
9. **Surface uncertainty.** If you're not confident about classification, set `notes` starting with `AUTO-CLASSIFIED:` and explain. Reply to user mentioning the uncertainty so they can correct.
10. **Never edit the markdown summaries.** `tracking/cashflow/YYYY-MM.md` files are auto-generated. Corrections always go to the CSV ledger. The markdown gets regenerated.

## Workflow

### Step 1: Parse the natural-language input

Extract:

| Field | How |
|---|---|
| **date** | Default today (`YYYY-MM-DD`) unless user specifies. Parse "yesterday", "last Monday", "Tết last year" etc. into ISO. |
| **amount_vnd** | Convert "200K"→200000, "1M"→1000000, "1.5M"→1500000, "1tr"→1000000, "1tỷ"→1000000000. Always integer. |
| **description** | Free-form Vietnamese / English. Preserve diacritics. Strip leading "for" / "paid for" filler if present. |
| **payment hints** | "by card" → Trang Credit Card. "cash" / "tiền mặt" → Treasury. "Visa" → Trang Credit Card. Default Treasury if unspecified. |
| **person/property hints** | "for Min" → tag `min`. "for Đan" → tag `dan`. "TKH" → property=TKH. "Hado", "Centrosa" → property=Hado Centrosa. "P21608", "Panoma" → property=Panoma. "LHP" → property=Le Hong Phong. |

### Step 2: Classify against VOCABULARY

Read `tracking/ledger/VOCABULARY.md` if you don't already have its contents in context. Map description + hints to:

| Field | Default behavior |
|---|---|
| `kind` | `expense` unless: "received" / "got" / "paid by [tenant]" → income; "Bảo ck" / "transferred to me" → transfer; "refund" / "claim" / "returned" → refund |
| `category` | Best match in vocabulary. Common: Everyday (food, snacks), Children, Home, Transportation, Utilities, Medical, Entertainment, Travel, Renovation. |
| `subcategory` | Match per-category vocabulary (Restaurants, Groceries, School, Maintenance, etc.) |
| `funding_source` | From hint, or Treasury if cash-implied |
| `property` | Only if explicit / clearly implied. Otherwise empty. |
| `tags` | Pipe-separated. Add all that apply: `min`, `dan`, `nanny`, `nanny-day`, `nanny-night`, `vaccine`, `ivf`, `renovation`, `tkh`, `parents`, `gift-given`, `gift-received`, `tet`, `travel`, `2-month-batch`, etc. |

If you're <70% confident on any field, set it to your best guess AND add a note: `AUTO-CLASSIFIED: not sure if [field] should be X or Y; please confirm.`

If you're <30% confident overall, **stop and ask the user** before appending.

### Step 3: Generate ID

```python
import hashlib
from datetime import datetime, timezone

now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
content_hash = hashlib.sha256(f"{date}|{amount_vnd}|{description}".encode()).hexdigest()[:6]
id = f"tx:hermes:{now_iso}:{content_hash}"
```

### Step 4: Compose the row

CSV header (already in file):
```
id,date,amount_vnd,kind,description,category,subcategory,funding_source,property,tags,source,source_ref,added_at,added_by,notes
```

Required for every Hermes append:
- `source` = `hermes`
- `source_ref` = the message identifier (e.g. `telegram-msg-12345`) or `chat-direct` if interactive Claude Code
- `added_at` = same UTC timestamp as in the ID
- `added_by` = `hermes`

CSV escape rules (use Python `csv.writer` to avoid bugs):
- Field with comma, double-quote, or newline → wrap in double-quotes
- Embedded double-quote → double it (`""`)
- Pipe in `tags` → literal, no escape

### Step 5: Append the row

Use Python with the `csv` module to append safely:

```python
import csv
from pathlib import Path

ledger = Path("tracking/ledger/transactions.csv")
fieldnames = ["id", "date", "amount_vnd", "kind", "description",
              "category", "subcategory", "funding_source", "property", "tags",
              "source", "source_ref", "added_at", "added_by", "notes"]

# Append in append mode; do NOT write header (already exists)
with ledger.open("a", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames, quoting=csv.QUOTE_MINIMAL)
    writer.writerow(row_dict)
```

### Step 6: Validate

Run `python infra/scripts/cashflow/validate_ledger.py`. Capture the exit code.

- **Exit 0 (pass):** continue to Step 7.
- **Exit 1 (fail):** revert the append. Read the file, drop the last line, write back. Surface the validation errors verbatim to the user. Do NOT proceed.

To revert the last appended line:
```python
lines = ledger.read_text(encoding="utf-8").splitlines()
ledger.write_text("\n".join(lines[:-1]) + "\n", encoding="utf-8")
```

### Step 7: Optionally regenerate the affected month's markdown

Default: skip this step (lazy regen pattern from the research note). The launchd job (if installed) refreshes daily, OR the user can run `python infra/scripts/cashflow/regenerate_monthly.py YYYY-MM` manually.

If the user explicitly wants fresh markdown ("show me the updated April file"), run:
```bash
python infra/scripts/cashflow/regenerate_monthly.py <YYYY-MM of the appended date>
```

### Step 8: Confirm to user

Reply with structured info so the user can spot misclassification:

```
Logged ✓
  ID: tx:hermes:2026-05-04T15:23:01:abc123
  Date: 2026-05-04
  Amount: 200,000 VND
  Description: Coffee at Highlands
  Kind: expense
  Category: Everyday > Restaurants
  Paid from: Trang Credit Card
  Tags: (none)
```

If you flagged uncertainty in `notes`, surface it: "Note: I classified this as Restaurants. If it's actually Snack, reply 'fix to Snack'."

## Inline corrections (cashflow-correct logic embedded)

If the user's NEXT message is a correction:
- "fix that last one to category Snack" → find the row by recent timestamp + your last ID; rewrite category column
- "wait, the amount was 250K not 200K" → find by recent timestamp; rewrite amount_vnd
- "I meant Đan not Min" → find by recent timestamp; rewrite tags

For each correction:
1. Read ledger, find the row by ID (you have it from Step 8 confirmation)
2. Modify the relevant column
3. Append to that row's `notes`: `edited YYYY-MM-DD by hermes: <field> was X, now Y; reason: user inline correction`
4. Rewrite the file (whole file, since CSV append-only mode can't edit in place — use Python's `csv` module to read all rows, modify the target, write all back atomically)
5. Re-validate
6. Confirm: "Updated ID: ... → category is now Snack."

For corrections to historical rows (not the last one), or bulk corrections, ask the user to use `cashflow-correct` instead.

## Worked examples

### Example 1: simple expense, fully resolved

User: `200K coffee at Highlands today, paid by card`

Skill:
1. Parse: date=today, amount=200000, description="Coffee at Highlands", payment="card" → Trang Credit Card
2. Classify: kind=expense, category=Everyday, subcategory=Restaurants, funding_source=Trang Credit Card, property="", tags=""
3. ID: `tx:hermes:2026-05-04T15:23:01:a3f5b2`
4. Append row, validate, confirm.

Reply:
```
Logged ✓
  Date: 2026-05-04, 200,000 VND
  Coffee at Highlands → Everyday > Restaurants, Trang Credit Card
  ID: tx:hermes:2026-05-04T15:23:01:a3f5b2
```

### Example 2: nanny payment with property + person tags

User: `paid Chị Hường 7M for nanny day care this month, cash`

Skill:
1. Parse: date=today, amount=7000000, description="Chị Hường nanny day care this month", payment="cash" → Treasury
2. Classify: kind=expense, category=Children, subcategory=Childcare, funding=Treasury, tags="min|nanny|nanny-day"
3. Append, validate, confirm.

### Example 3: rental income with tag

User: `LHP tenant paid 28M for May+June`

Skill:
1. Parse: date=today, amount=28000000, description="LHP tenant paid for May+June"
2. Classify: kind=income, category=Rental, subcategory="Le Hong Phong", funding=Treasury (default), property=Le Hong Phong, tags="rental|2-month-batch"
3. Append, validate, confirm.

### Example 4: low-confidence, ASK user

User: `1.2M something at the place yesterday`

Skill:
1. Parse: date=yesterday's ISO, amount=1200000, description="something at the place" — too vague
2. Stop. Reply: "I can't classify '1.2M something at the place yesterday' confidently. Could you tell me: (a) what it was for (food, school, gift, etc.), and (b) how you paid (cash, card)?"
3. Wait for clarification before appending.

### Example 5: novel category, ASK to update VOCAB

User: `1M veterinarian for the dog`

Skill:
1. Parse and classify: would map to Pets, but "Pets" only has 1 historical row and may not have a "Vet" subcategory in VOCABULARY.md.
2. Read VOCABULARY.md → Pets > Vet IS listed. Proceed with `category=Pets, subcategory=Vet`.
3. Append, validate, confirm.

(Counter-example: if user says `5M for car wash subscription` and "Car wash subscription" isn't in any subcategory, ask the user: "Should I add 'Car wash' under Transportation, or treat as Personal?")

### Example 6: inline correction

User: (after Example 1) `wait, that was actually paid in cash, not card`

Skill:
1. Find the just-appended row by ID `tx:hermes:2026-05-04T15:23:01:a3f5b2`.
2. Modify `funding_source` column from "Trang Credit Card" to "Treasury".
3. Append to `notes`: `edited 2026-05-04 by hermes: funding_source was Trang Credit Card, now Treasury; reason: user inline correction`
4. Rewrite file, re-validate, confirm: "Updated. Coffee at Highlands now shows funding=Treasury."

## Anti-patterns

- ❌ **Inventing categories** like `Coffee` or `Subscriptions`. Use existing vocabulary or ask user.
- ❌ **Silent classification on ambiguous input.** If you'd guess and shrug, ASK instead.
- ❌ **Skipping validation.** Every append → validate. Every correction → validate.
- ❌ **Editing markdown files.** They're derived. Even if user says "update the April markdown directly," push back: edit the CSV; regen produces the markdown.
- ❌ **Using emoji in vocabulary fields.** Trang's xlsx had `🌱 Everyday` but the ledger uses `Everyday`.
- ❌ **Stripping Vietnamese diacritics from description.** Keep them.
- ❌ **Using `null` / `none` / `-` for empty fields.** Empty string only.
- ❌ **Negative amount_vnd.** Sign comes from `kind`. A refund is `kind=refund` with positive amount, not `kind=expense` with negative amount.
- ❌ **Not surfacing the new ID** in the confirmation. The user needs the ID to refer back for corrections.
- ❌ **Trying to dedupe across sources.** That's a bank-import job (Phase 6). Each Hermes append is a new transaction; trust the user.

## Reusable code patterns

When implementing the actual append, lean on these existing modules:

- `infra/scripts/cashflow/backfill_xlsx.py` has the `Row` dataclass + `to_csv_dict()` method you can mirror
- `infra/scripts/cashflow/backfill_xlsx.py` has classification heuristics (`classify_in_tx`, `classify_min`) for inspiration
- Python stdlib `csv.DictWriter` handles all escaping correctly — don't roll your own

## Edge cases worth knowing

- **Today's date crossing midnight UTC**: use the user's local Asia/Ho_Chi_Minh date for `date`, but UTC for `added_at`. They can disagree by a few hours; that's fine.
- **Multi-purpose payments** ("100K, half for Min half for Đan"): split into 2 rows, 50K each, with different tags. Confirm with user before splitting.
- **Foreign currency**: convert to VND at user's stated rate or ask. Note original in `notes`: `Original: USD 50, converted at 25,400 VND/USD`.
- **Future-dated transactions**: validation rule 5 allows ±1 day grace. Anything further in the future is rejected; ask user if they meant a past date.
- **Han transferring to Trang for a specific purpose**: `kind=transfer`, category=Transfer, tags=`han-funding` (or `renovation-funding` if earmarked).
- **Refunds**: `kind=refund`, positive amount, category=Refund, subcategory naming the original purpose (e.g. "IVF unused funds", "Insurance"). Notes should reference the offset.

## Related skills

- `cashflow-close` — batch ingestion of screenshots / CSVs. This skill (cashflow-append) is for single inline transactions; cashflow-close is for bulk.
- `cashflow-correct` — bulk historical row edits. This skill handles inline corrections to recent appends; cashflow-correct handles "all the renovation rows in 2025-08 should have property=TKH explicitly".
- `cashflow-report` — querying / reports. Not for adding data.

## References

- SPEC-001: `docs/specs/SPEC-001-cashflow-ledger.md`
- Hermes contract: `tracking/ledger/README.md`
- Vocabulary: `tracking/ledger/VOCABULARY.md`
- Helper scripts: `infra/scripts/cashflow/`
- ADR 0015: `decisions/0015-cashflow-ledger-single-csv.md`
