---
name: cashflow-report
description: Use when the user asks for a cashflow analysis or report from the family-office ledger. Trigger phrases include "cashflow report for [period]", "monthly review [YYYY-MM]", "quarterly review [YYYY-QN]", "annual summary [YYYY]", "year-over-year", "category trend", "spending by [category|property|tag|funding source]", "Min costs in [period]", "TKH renovation breakdown", "tag deep-dive [tagname]". Reads `tracking/ledger/transactions.csv` (the source of truth), produces a markdown report at `tracking/reports/<scope>/YYYY-MM-DD-<slug>.md` plus optional matplotlib charts at `docs/charts/<scope>/`. Reports are SEPARATE files (timestamped); do NOT edit existing cashflow markdown files. NOT for adding/editing transactions (use cashflow-append / cashflow-correct).
---

# Cashflow report

Produce on-demand reports from `tracking/ledger/transactions.csv`. Aimed at Han's periodic deep-dives: monthly summaries, quarterly reviews, annual PnL precursors, category/tag/property deep-dives.

Each invocation produces a fresh, timestamped markdown report (so the same report can be re-run with different filters and history is preserved). Charts saved as PNG.

## When to use

- User asks for any aggregate question that goes beyond the auto-generated `tracking/cashflow/YYYY-MM.md`:
  - `cashflow report for 2025-Q3`
  - `monthly review November 2025`
  - `annual summary 2025`
  - `year-over-year category trend`
  - `Min costs across the whole project`
  - `spending by property in 2025`
  - `tag deep-dive renovation`

## When NOT to use

- Add a single transaction → `cashflow-append`
- Bulk edit historical rows → `cashflow-correct`
- Batch ingest screenshots / CSVs → `cashflow-close`
- Read a SINGLE month at a glance → just open `tracking/cashflow/YYYY-MM.md` (already auto-generated)

## Hard rules

1. **Reports are separate files.** Never edit `tracking/cashflow/YYYY-MM.md` (those are derived views). Reports go to `tracking/reports/<scope>/YYYY-MM-DD-<slug>.md`.
2. **Timestamps in filenames.** Format: `YYYY-MM-DD-<slug>.md` where YYYY-MM-DD is today's date. Lets the user re-run with different parameters; each output is a distinct artifact.
3. **Charts use light theme.** Per Han's CLAUDE.md preference. Use `matplotlib.style.use('default')` or set a light-bg explicitly. White background, dark text/lines.
4. **No em dashes.** Use hyphens, semicolons, commas, or split sentences. Per Han's CLAUDE.md absolute rule.
5. **Source of truth is the ledger.** Always read `tracking/ledger/transactions.csv` directly. Do NOT compute aggregates from `tracking/cashflow/YYYY-MM.md` (those are views; cycle would create drift).
6. **Vocabulary terms must exist.** If user asks for a tag/category/property that doesn't appear in the ledger, surface that ("no rows tagged 'X' in the ledger") rather than producing an empty report.
7. **Net cashflow excludes transfers.** When computing "income - expenses", `kind=transfer` is excluded (intra-household balance moves). `refund` is positive (offsets expense).
8. **All charts get a saved file path AND linked from the markdown.** Don't generate ephemeral charts.

## Standard reports

### Monthly summary

User: `monthly review 2025-11` or `cashflow report for November 2025`

Output: `tracking/reports/monthly/YYYY-MM-DD-2025-11.md`

Contents:
- Total income (recognized) / total expenses / net for the month
- Breakdown by category (table, sorted by amount desc)
- Top 10 largest single transactions with descriptions
- Property attribution summary (if any property-tagged rows)
- Funding source split (Treasury / Trang Credit Card / others)
- YoY comparison vs same month prior year if data exists (table: this-month, last-year-this-month, % delta)
- Optional chart: bar chart of expenses by category (PNG)

### Quarterly review

User: `quarterly review 2025-Q3`

Output: `tracking/reports/quarterly/YYYY-MM-DD-2025-Q3.md`

Contents:
- Per-month totals across the 3 months (table)
- Category breakdown across the quarter
- Notable spikes / anomalies (auto-detect: any month >2x the median monthly total)
- Optional chart: stacked bar by month + category (PNG)
- Optional chart: trend line for top 5 categories (PNG)

### Annual summary

User: `annual summary 2025` or `2025 PnL precursor`

Output: `tracking/reports/annual/YYYY-MM-DD-2025.md`

Contents:
- Year totals (income, expenses, transfers, refunds, net)
- Per-month overview table (12 rows)
- Category breakdown for the year
- Per-property spending
- Per-tag spending (highlight `min`, `renovation`, `ivf`, `dan`, `pregnancy`, `postpartum`)
- Biggest one-off transactions (top 20)
- Implicit savings rate flag if Han-side income is missing ("note: this only reflects wife-side income")
- Optional chart: monthly trend line (income vs expense) (PNG)

### Tag deep-dive

User: `tag deep-dive renovation` or `Min costs across the project`

Output: `tracking/reports/tags/YYYY-MM-DD-<tagname>.md`

Contents:
- All rows with that tag (chronological table; full description preserved)
- Subtotals by month, by category, by property
- Optional chart: stacked bars by month, color-coded by category (PNG)

### Property report

User: `property report TKH 2025` or `Hado Centrosa expenses`

Output: `tracking/reports/properties/YYYY-MM-DD-<property>.md`

Contents:
- All rows attributed to that property (filter `property=<name>`) over the requested period
- Subtotals: Renovation, Maintenance, Property tax, Other
- Optional chart: monthly bar (PNG)

## Workflow

### Step 1: Parse the request

Identify:
- Report type (monthly / quarterly / annual / tag deep-dive / property / custom)
- Filter parameters (date range, tag, category, property)
- Chart preference (default: include charts; user can opt out with "no charts")

If ambiguous, ask. Don't guess between "Q3 2025" and "Q3 2026" — use absolute dates or ask.

### Step 2: Load the ledger

```python
import csv
from pathlib import Path
ledger = Path("tracking/ledger/transactions.csv")
with ledger.open(newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))
# Type cast amount; split tags
for r in rows:
    r["amount_vnd"] = int(r["amount_vnd"])
    r["tags_set"] = set(r["tags"].split("|")) if r["tags"] else set()
```

### Step 3: Filter

Apply the filters per report type. Use Python list comprehensions:

```python
# Monthly summary for 2025-11
filtered = [r for r in rows if r["date"].startswith("2025-11")]

# Tag deep-dive for renovation
filtered = [r for r in rows if "renovation" in r["tags_set"]]

# Property report for TKH 2025
filtered = [r for r in rows if r["property"] == "TKH" and r["date"].startswith("2025")]
```

### Step 4: Aggregate

Build the tables per report type. Use `collections.defaultdict` for grouping:

```python
from collections import defaultdict
cat_totals = defaultdict(int)
for r in [x for x in filtered if x["kind"] == "expense"]:
    cat_totals[r["category"]] += r["amount_vnd"]
```

### Step 5: Render markdown

Build the report content as a list of strings, write to `tracking/reports/<scope>/YYYY-MM-DD-<slug>.md`:

```python
from datetime import date
today = date.today().isoformat()
out_dir = Path(f"tracking/reports/{scope}")
out_dir.mkdir(parents=True, exist_ok=True)
out_path = out_dir / f"{today}-{slug}.md"
out_path.write_text("\n".join(md_lines), encoding="utf-8")
```

Frontmatter every report:
```yaml
---
title: <Report title>
type: report
scope: <monthly|quarterly|annual|tag|property|custom>
generated_at: <ISO timestamp>
ledger_source: tracking/ledger/transactions.csv
filter: <human description of the filter>
---
```

Header line in body:
```
> Generated YYYY-MM-DD by cashflow-report skill from `tracking/ledger/transactions.csv`. Re-run for fresh figures.
```

### Step 6: Charts (optional)

Use matplotlib with light theme. Save PNG to `docs/charts/<scope>/YYYY-MM-DD-<slug>.png`. Link from the markdown:

```markdown
![Expenses by category](../../../docs/charts/monthly/2026-05-04-2025-11-by-category.png)
```

Recommended chart code skeleton:

```python
import matplotlib
matplotlib.use("Agg")  # headless
import matplotlib.pyplot as plt
plt.style.use("default")  # light theme
fig, ax = plt.subplots(figsize=(10, 6), facecolor="white")
ax.set_facecolor("white")
# ... plot ...
ax.set_title("Expenses by Category - 2025-11", color="#222")
ax.tick_params(colors="#222")
fig.tight_layout()
fig.savefig(chart_path, dpi=120, facecolor="white")
plt.close(fig)
```

Common chart types:
- Bar chart: categories vs VND amounts
- Stacked bar: months × categories
- Line: monthly trend over time
- Horizontal bar: top N transactions

If matplotlib isn't installed: `uv run --with matplotlib python <script>` works without polluting the system. The skill should use this pattern.

### Step 7: Confirm to user

```
Report ✓
  File: tracking/reports/monthly/2026-05-04-2025-11.md
  Chart: docs/charts/monthly/2026-05-04-2025-11-by-category.png
  Coverage: 2025-11 (245 transactions, 58.1M VND in expenses)
  Top category: Everyday (26.3M, 45%)
```

## Worked example

User: `quarterly review 2025-Q3`

Skill:
1. Parse: scope=quarterly, period=2025-Q3 (months 07, 08, 09)
2. Load ledger
3. Filter: rows where date in `[2025-07-01, 2025-09-30]`
4. Aggregate: per-month totals, per-category totals, top 10 transactions, anomaly detection
5. Build markdown:
   - Q3 2025 totals: 257M / 145M / 105M expenses by month (sum 507M)
   - Spike: July had 257M (~2x median), driven by 71M Children (Q3 school) + 141M renovation
   - Category breakdown table
   - Top 10 single transactions (probably the 3 × 70M Lượng renovation tranches at top)
6. Chart: stacked bar by month × category (light theme)
7. Save to `tracking/reports/quarterly/2026-05-04-2025-Q3.md` + `docs/charts/quarterly/2026-05-04-2025-Q3-stacked.png`
8. Confirm

## Anti-patterns

- ❌ **Edit `tracking/cashflow/YYYY-MM.md`.** Those are auto-generated views; reports go to `tracking/reports/`.
- ❌ **Read aggregates from the markdown views instead of the CSV.** Always go to source.
- ❌ **Ephemeral charts** (display only, no save). Save every chart with a path.
- ❌ **Em dashes anywhere** in report text. Hyphens, semicolons, splits.
- ❌ **Dark-theme charts.** Light theme always.
- ❌ **Skip chart for time-series data.** Numbers in tables are fine; trends benefit from a visual.
- ❌ **Mix kind=transfer into income totals.** Transfers are intra-household; exclude from income/expense math.
- ❌ **Fabricate YoY when prior year is empty.** If the comparison period has 0 rows, omit the YoY block; don't show "100% growth from 0".
- ❌ **Auto-commit reports.** Generate, surface, let user decide whether to commit.

## Edge cases

- **Period straddles year boundary** (e.g. "fiscal year ending June"): parse explicit start+end dates; don't assume calendar year.
- **Tag deep-dive on a tag with 0 rows**: surface "no rows tagged 'X' in ledger; current tags: [list]" rather than empty report.
- **Top-N when N > matched rows**: report fewer; don't pad.
- **Refunds in totals**: net them against expenses for the period; show separately in a "Refunds (offsets)" line.
- **Han-side income missing**: every annual/quarterly summary should flag this near the savings rate ("Real savings rate not computable until Han-side income ingested via bank statements").

## Reusable patterns

- `infra/scripts/cashflow/regenerate_monthly.py` has section-rendering logic (Income / Expenses by category / Subcategory / Funding source / Summary). Borrow the structure for monthly reports; extend for quarterly/annual/property/tag.
- `tracking/ledger/README.md` has DuckDB query examples that translate directly to Python `csv` filtering.

## Related skills

- `cashflow-append` — single transaction add
- `cashflow-correct` — bulk historical edits
- `cashflow-close` — batch ingestion
- `reconcile-properties` — useful to run BEFORE a property report if the property data may be stale across repos

## References

- ADR 0015: `decisions/0015-cashflow-ledger-single-csv.md`
- SPEC-001: `docs/specs/SPEC-001-cashflow-ledger.md`
- Research note (analytics tool choice): `docs/research/cashflow-ledger-scaling-and-analytics.md`
- Vocabulary: `tracking/ledger/VOCABULARY.md`
