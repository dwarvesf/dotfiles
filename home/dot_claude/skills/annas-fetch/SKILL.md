---
name: annas-fetch
description: Use when the user wants to download a book or paper from Anna's Archive without clicking through the site, OR wants to browse the most-downloaded / top books on a topic. Trigger phrases include "download [title] from anna", "grab this MD5", "fetch [book] epub", "find me [book] on annas-archive", "top books on [topic]", "most downloaded [topic] books", "browse anna for [topic]", or any annas-archive.gl/.li/.in/.pm/.org URL pasted in chat. Drives the ops-toolkit annas-fetch CLI; default sort is popularity (mirror count + format quality + recency); resolves the member key from 1Password via `op run`; lands files in ~/Downloads/annas. NOT for free-tier downloads (we use the member fast-download API only) and NOT for bulk scraping.
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
2. **Default base URL is `https://annas-archive.gl`** (current primary as of 2026-05-10). The CLI has mirror fallback; if the user reports the primary has rotated, update `DEFAULT_BASE` in `annas_fetch.py` or pass `ANNAS_BASE_URL`.
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

No key needed for search. Default `--sort popularity` ranks by `mirror_count + format_quality + 0.5*recency + edition_bonus`. Output columns: `MD5  SCORE  EXT  YEAR  Nm  e<N>  TITLE` (`Nm` = mirror count; `e<N>` only shown when explicit edition > 1).

**Intent split (important)**: `popularity` answers "the version most people read"; `--sort newest` answers "the absolute latest upload, even if barely circulated". The popularity sort includes a capped edition bonus so 2nd/3rd editions usually surface above older editions of the same book — but mirror count still dominates for similarly-edition'd results. If the user asks "is there a newer edition?" and popularity didn't surface one, retry with `--sort newest`.

Show top 5-10 results to the user. Ask which to fetch unless one is an unambiguous match (e.g., user said "DDIA" and the top result is a 2-mirror epub of DDIA).

### Step 3: Browse (discovery / top-N for a topic)

```bash
python3 ~/workspace/tieubao/ops-toolkit/tools/annas-fetch/annas_fetch.py \
  browse "<topic>" --ext <epub> --limit 20
```

Same backend as search, but with broader defaults: `--limit 20`, popularity sort. Use this when the user wants a survey of what's available on a topic, not a specific book. Frame the response as "top books on X" rather than "search results for X".

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

The CLI prints the saved path on stdout and `# quota: ...` on stderr if the API returned quota info.

Report to the user:
- Saved path
- File size (`ls -lh`)
- Quota remaining (if surfaced): "X of 75 fast-downloads left today"

### Step 5: Failure handling

- **`download_url` missing across all 9 attempts** → API may have shifted field names. Inspect one raw response: `op run --env-file /tmp/annas.env -- python3 -c "import sys; sys.path.insert(0, '/Users/tieubao/workspace/tieubao/ops-toolkit/tools/annas-fetch'); from annas_fetch import fast_download_url; import json; print(json.dumps(fast_download_url('<md5>'), indent=2))"`. Patch the field name in the CLI.
- **All mirrors fail at transport** → check `https://annas-archive.gl` in a browser. If the domain rotated, update `DEFAULT_BASE` in the script.
- **Quota exceeded** → tell the user; do not retry.
- **Captcha / Cloudflare challenge in response** → member API should bypass these; if hit, the key may be invalid or expired. Verify the 1Password ref.
- **Search results look like garbage / empty** → AA HTML markup may have shifted. Run `python3 -m unittest discover ~/workspace/tieubao/ops-toolkit/tools/annas-fetch/tests -v` — if parser tests still pass against fixtures but live results are broken, refresh fixtures with `curl ... > tests/fixtures/<name>.html` and update assertions.

## What this skill does NOT do

- No library catalog, no dedup against existing local files.
- No tagging or renaming beyond what AA returns in `Content-Disposition`.
- No push to Calibre / Readwise / etc. (compose with another skill if needed).
- No bulk fetch loop. Each `fetch` invocation = one MD5.

## References

- Tool source: `~/workspace/tieubao/ops-toolkit/tools/annas-fetch/`
- Spec: `ops-toolkit/tools/annas-fetch/SPEC.md`
- Tests: `python3 -m unittest discover ~/workspace/tieubao/ops-toolkit/tools/annas-fetch/tests -v` (no network) plus `RUN_LIVE_SMOKE=1 python3 tests/smoke_live.py` (network, no fetch)
- API: `GET /dyn/api/fast_download.json?md5=<hash>&key=<member_key>&path_index=<0..2>&domain_index=<0..2>` → JSON `{download_url, account_fast_download_info, ...}` or `{error, ...}`
