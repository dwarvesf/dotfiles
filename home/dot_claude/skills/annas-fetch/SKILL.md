---
name: annas-fetch
description: Use when the user wants to download a book or paper from Anna's Archive without clicking through the site, OR wants to browse the most-downloaded / top books on a topic. Trigger phrases include "download [title] from anna", "via anna archive", "search anna for [book]", "search for [book] on anna", "find me [book] on annas-archive", "grab this MD5", "fetch [book] epub", "top books on [topic]", "most downloaded [topic] books", "browse anna for [topic]", plus the bare strings "anna archive", "annas archive", "anna's archive", "annas-archive", "annas", "shadow library", "libgen", "library genesis", "z-library" (as a fallback phrasing), or any annas-archive.gl/.li/.in/.pm/.org URL pasted in chat. Drives the ops-toolkit annas-fetch CLI; default sort is popularity (mirror count + format quality + recency); resolves the member key from 1Password via `op run`; lands files in ~/Downloads/annas. NOT for free-tier downloads (we use the member fast-download API only) and NOT for bulk scraping.
---

# annas-fetch

Search, browse, and download books from Anna's Archive via the **member fast-download JSON API**. No browser clicks, no JavaScript scraping. Wraps the stdlib-only CLI at `~/workspace/tieubao/ops-toolkit/tools/annas-fetch/`. Spec: `ops-toolkit/tools/annas-fetch/SPEC.md`.

## When to use

- User pastes a title and asks to download: "find me Designing Data-Intensive Applications epub", "grab The Body Keeps the Score".
- User pastes an annas-archive URL like `https://annas-archive.gl/md5/abc...` or `.../search?q=...`.
- User gives a 32-char hex MD5 and asks to fetch it.
- User wants discovery: "what are the top books on personal finance?", "most downloaded books on [topic]", "browse anna for [topic]".

## When NOT to use

- User wants the **free** slow-download flow → tell them to click through the site; this skill only uses the member API.
- User wants bulk scraping (>10 books in one run) → talk first; daily quota will rate-limit, plus larger questions about ToS / IP-rotation we shouldn't auto-decide.
- User wants to search a different shadow library (LibGen direct, Sci-Hub, Z-Library) → different tool needed.

## Hard rules

1. **Never hardcode the secret key.** Always resolve from 1Password at runtime. The skill uses `op run --env-file <tempfile>` (the `secret-guard` hook blocks raw `op read` even in nested contexts). The Python CLI reads `ANNAS_SECRET_KEY` from env; the skill is responsible for setting it for the subprocess only.
2. **Default base URL is `https://annas-archive.gl`** (current primary as of 2026-05-10). The CLI iterates `MIRRORS` on transport failure, then auto-discovers replacements via Wikipedia (then Anna's blog) when every mirror in the effective list dies in one invocation. Discovery result is cached at `~/.cache/annas-fetch/mirrors.json` (30-day TTL). Manual edits to `DEFAULT_BASE` / `ANNAS_BASE_URL` are still supported but rarely needed; for a forced refresh run `annas-fetch mirror-discover --force`. See Spec 08.
3. **Default output is `~/Downloads/annas/`.** Never write into a consumer repo. Books are not repo content.
4. **Confirm before downloading >3 files in one session.** Member tier daily quota is ~75 fast-downloads; bulk runs burn it fast.
5. **Surface the quota line.** When the CLI prints `# quota: ...` to stderr, relay `downloads_left / downloads_per_day` to the user.

## Workflow

### Step 1: Determine the input shape

| User input | Action |
|---|---|
| 32-char hex MD5 | Skip search, go to Step 4 (fetch). |
| `https://annas-archive.*/md5/<hash>` URL | Extract MD5, go to Step 4. |
| Specific title / author / "find me X" | Run `search` (Step 2). |
| Topic / "top books on X" / "most downloaded X" | Run `browse` (Step 3). |
| `https://annas-archive.*/search?q=...` URL | Re-issue as `search` (Step 2). |

### Step 2: Search (known-item lookup)

```bash
python3 ~/workspace/tieubao/ops-toolkit/tools/annas-fetch/annas_fetch.py \
  search "<query>" --ext <epub|pdf|...> --limit 10
```

No key needed for search. Default `--sort popularity` ranks by `log10(downloads+1) + 0.3*mirror_count + format_quality + 0.5*recency + edition_bonus` when the per-MD5 stats endpoint is reachable (default since SPEC 09), falling back to the mirror-dominant v0.2 formula when it isn't. Output columns: `MD5  SCORE  EXT  YEAR  Nm  DL  e<N>  TITLE` where `DL` is the lifetime download count (`-` when the stats endpoint failed for that MD5).

**Intent split (important)**: pick the sort by what the user actually wants:

| User intent | Sort | Why |
|---|---|---|
| "the version most people read" / mainstream pick | `popularity` (default) | log10(downloads) + 0.3*mirrors + format + recency + capped edition bonus. Demand-weighted via the per-MD5 stats endpoint; fallback to v0.2 mirror-only formula when stats fail. |
| "the absolute latest upload, even if barely circulated" | `--sort newest` | AA server-side upload-date sort (NOT publication year). |
| Mix of "canonical" + "freshly uploaded" | `browse --hybrid` | Issues popularity + newest in sequence, dedups by MD5, round-robins. Marks overlap with 🆕. |

Popularity includes a capped edition bonus so 2nd/3rd editions usually surface above older editions; downloads still dominates within the same edition. If the user asks "is there a newer edition?" and popularity didn't surface one, retry with `--sort newest`.

**Grouping** (`browse` defaults to on, `search` defaults to off): AA often has 3-5 separate uploads of the same book under different MD5s. The grouped view collapses them by normalized title prefix + year tolerance ±1 and shows aggregate downloads. Flags: `--group-by-title` (force on), `--no-group` (force off).

**Filter flags** stack with any sort (all AND):

| Flag | Purpose | Notes |
|---|---|---|
| `--ext epub` | extension filter | one extension at a time |
| `--author "Name"` | author filter | folded into `q=` as `author:"X"` |
| `--lang en` (repeatable) | **soft** language preference | does NOT exclude other languages — AA's `lang=` is a ranking hint |
| `--exclude-lang vi` (repeatable) | **hard** language exclusion | emits AA's `lang=anti__<iso>`; verified to actually drop tagged content |
| `--year 2017` | single publication year | mutually exclusive with `--year-range` |
| `--year-range 2015-2020` | inclusive range | inverted ranges rejected at argparse time |

When the user says "give me an English book on X" — interpret as `--exclude-lang vi` (or other non-English) rather than `--lang en`, because `--lang` is soft.

Show top 5-10 results to the user. Ask which to fetch unless one is an unambiguous match (e.g., user said "DDIA" and the top result is a 2-mirror epub of DDIA).

### Step 3: Browse (discovery / top-N for a topic)

```bash
python3 ~/workspace/tieubao/ops-toolkit/tools/annas-fetch/annas_fetch.py \
  browse "<topic>" --ext <epub> --limit 20

# Hybrid mode: popularity + newest merged round-robin
python3 .../annas_fetch.py browse "<topic>" --hybrid --ext epub --limit 20
```

Same backend as search, but with broader defaults: `--limit 20`, popularity sort. Use this when the user wants a survey of what's available on a topic, not a specific book. Frame the response as "top books on X" rather than "search results for X".

Use `--hybrid` when the user wants both canonical books and recent uploads. The 🆕 marker on a row means it appears in *both* streams.

### Step 4: Fetch (requires member key)

The skill must run fetch via `op run` so the key never lands in shell:

```bash
echo 'ANNAS_SECRET_KEY=op://Toolkit/annas-archive/credential' > /tmp/annas.env
env -u OP_SERVICE_ACCOUNT_TOKEN op run --env-file /tmp/annas.env -- \
  python3 ~/workspace/tieubao/ops-toolkit/tools/annas-fetch/annas_fetch.py \
  fetch <md5> --out ~/Downloads/annas
```

(`env -u OP_SERVICE_ACCOUNT_TOKEN` forces fall-through to 1Password desktop integration; the env-injected service-account token is dead per 2026-05-10 reference memory.)

The ref `op://Toolkit/annas-archive/credential` is the confirmed location. If `op read` fails with "field not found" at the `credential` slot, try `password` or `token` before assuming the item is missing.

The CLI prints the saved path on stdout, persists a quota row to `~/.cache/annas-fetch/quota.jsonl`, and emits `# quota: ...` on stderr if the API returned quota info. On every fetch it also stderr-warns when the local count today is >=70 of 75.

**Dedup before fetching** (when the user has built a library index): add `--check-library` to skip when the MD5 is already on disk. The CLI exits 2 without making any HTTP call. Add `--force` to fetch anyway.

```bash
... fetch <md5> --out ~/Downloads/annas --check-library
```

Report to the user:
- Saved path
- File size (`ls -lh`)
- Quota remaining (if surfaced): "X of 75 fast-downloads left today"

### Step 4b: Details on a single MD5 (SPEC 09)

```bash
python3 ~/workspace/tieubao/ops-toolkit/tools/annas-fetch/annas_fetch.py \
  details <md5>
```

No member key needed. Prints `total / last 7d / last 30d / fetched_at`. Use when the user asks "how popular is this MD5?", "how many people downloaded X?", or has selected a candidate from a search list and wants the full popularity story before fetching. `--json` emits the full timeseries.

The endpoint is `GET /dyn/downloads/stats/<md5>` — public, unauthenticated. v0.2 of this skill incorrectly claimed AA "doesn't expose download counts"; that was a recon gap, corrected 2026-05-13.

### Step 5: Housekeeping subcommands (when the user asks)

| User intent | Subcommand |
|---|---|
| "how much quota do I have left?" | `annas-fetch quota` — prints today's local count + last AA `account_fast_download_info` blob |
| "how many downloads does <md5> have?" | `annas-fetch details <md5>` — public stats endpoint, no key needed (see Step 4b) |
| "build the local library index" | `annas-fetch library scan --path ~/Downloads/annas` — walks recursively, hashes books, writes `~/.cache/annas-fetch/library.jsonl`. Add `--full` to rebuild from scratch. |
| "do I already have <md5>?" | `annas-fetch library check <md5>` — exits 0 + path on hit, 1 on miss, 3 if no index |
| "are the AA mirrors alive?" / "is .gl down?" | `annas-fetch mirror-check` — probes every entry in `MIRRORS` with HEAD, prints latency table. Add `--json` for structured output. |
| "AA rotated all domains, find the new one" / "refresh the mirror list" | `annas-fetch mirror-discover [--force] [--json]` — scrapes the Anna's Archive Wikipedia page (then the blog) for current domains, writes `~/.cache/annas-fetch/mirrors.json`. Lazy auto-fallback already fires inside search/fetch on full failure; this verb is for explicit/manual refresh. |
| "AA's HTML changed, parser tests broken" | `annas-fetch dev refresh-fixtures` — re-pulls `tests/fixtures/*.html`. Run unit tests after to surface drift. Dev-only. |

None of these require the member key (only `fetch` does).

### Step 6: Failure handling

- **`download_url` missing across all 9 attempts** → API may have shifted field names. Inspect one raw response: `op run --env-file /tmp/annas.env -- python3 -c "import sys; sys.path.insert(0, '/Users/tieubao/workspace/tieubao/ops-toolkit/tools/annas-fetch'); from annas_fetch import fast_download_url; import json; print(json.dumps(fast_download_url('<md5>'), indent=2))"`. Patch the field name in the CLI.
- **All mirrors fail at transport** → the CLI now auto-recovers by scraping Wikipedia (then Anna's blog) for the current domain list. If even that fails (rare: Wikipedia and the blog would both have to be unreachable), run `annas-fetch mirror-check` to confirm baseline reachability and `annas-fetch mirror-discover --force --json` to inspect the discovery payload. Last-resort overrides are still `DEFAULT_BASE` or `ANNAS_BASE_URL`.
- **Quota exceeded** → tell the user; do not retry.
- **Captcha / Cloudflare challenge in response** → member API should bypass these; if hit, the key may be invalid or expired. Verify the 1Password ref.
- **Search results look like garbage / empty** → AA HTML markup may have shifted. Run `python3 -m unittest discover ~/workspace/tieubao/ops-toolkit/tools/annas-fetch/tests -v` — if parser tests still pass against fixtures but live results are broken, refresh fixtures with `annas-fetch dev refresh-fixtures` and re-run tests to surface what changed.

## What this skill does NOT do

- No tagging or renaming beyond what AA returns in `Content-Disposition`.
- No push to Calibre / Readwise / etc. (compose with another skill if needed).
- No bulk fetch loop. Each `fetch` invocation = one MD5.
- No quota enforcement. We warn at 70/75, AA blocks at 75. Don't retry on quota-exceeded.

## References

- Tool source: `~/workspace/tieubao/ops-toolkit/tools/annas-fetch/`
- Spec: `ops-toolkit/tools/annas-fetch/SPEC.md`
- Follow-up specs: `ops-toolkit/tools/annas-fetch/specs/` (filters, hybrid browse, library dedup, quota tracker, mirror-check, fixture refresh, mirror auto-discovery, download-stats; spec 05 parallel-probe is deferred)
- Tests: `python3 -m unittest discover ~/workspace/tieubao/ops-toolkit/tools/annas-fetch/tests -v` (no network, 157 cases) plus `RUN_LIVE_SMOKE=1 python3 tests/smoke_live.py` (9 cases, network, no fetch)
- APIs:
  - `GET /dyn/api/fast_download.json?md5=<hash>&key=<member_key>&path_index=<0..2>&domain_index=<0..2>` → JSON `{download_url, account_fast_download_info, ...}` or `{error, ...}` (member-key required, drives `fetch`)
  - `GET /dyn/downloads/stats/<md5>` → JSON `{total, timeseries_x, timeseries_y, downloads_total}` (public, drives `details` and the popularity enrichment in `search` / `browse`)
- Cache: `~/.cache/annas-fetch/` holds `quota.jsonl` (per-fetch row), `library.jsonl` (built by `library scan`), `mirrors.json` (auto-discovered mirror list, 30-day TTL), and `downloads.jsonl` (per-MD5 download counts, 24h TTL).
