---
name: learning-day-process
description: Use when Han drops a class transcript (Notion export, recording transcription) + optional screenshots into `_meta/` or similar location, and wants the day's content processed into the learning track structure. Trigger phrases include "process Day-NN", "wrap Day-NN", "tổng hợp transcript Day-NN", "ingest class transcript", "tôi vừa add transcript của buổi học", "Day-N của <topic>", or any case where Han has dropped a raw class material and wants the standard workflow. Produces FOUR artifacts: workbook (Day-NN.md), beginner companion with embedded bài tập (Day-NN-explained.md), practice notebook (Day-NN-practice.ipynb), and anki deck (qworld-day-NN.tsv + .apkg). Auto-invokes sibling skills `anki-builder` (deck generation), `concept-image-fetch` (Wikipedia/DDG visuals per concept), and `svg-knowledge-diagram` (inline teaching SVGs per concept). Applies to all `learning/<topic>/` tracks: quantum, mathematics, security, etc. NOT for ad-hoc concept questions (use concept-explain). NOT for non-class content (use ingest-to-wiki for general material).
---

# Learning Day Process

Process a class transcript + screenshots into the standard **4-artifact** output for any `learning/<topic>/` track in ops-toolkit. Output is reproducible:

1. **Workbook** (`Day-NN.md`) for the fluent-reader scan.
2. **Beginner companion** (`Day-NN-explained.md`) with embedded 🧮 Bài tập (exercises from the professor) + worked đáp án.
3. **Practice notebook** (`workbooks/<course>-day-NN.ipynb` + jupytext-paired `.py:percent` twin per SPEC-011) with executable Qiskit (or domain equivalent) code + bài tập as runnable cells. The RCSR C-step lands here. Commit only the `.py` (gitignored `.ipynb` is a build artifact).
4. **Anki deck** (`anki/qworld-day-NN.tsv` + `.apkg`) built via the sibling `anki-builder` skill.

Plus incremental glossary update (`GLOSSARY.md`).

Three sibling skills are auto-invoked: `anki-builder` (TSV → .apkg), `concept-image-fetch` (Wikipedia visuals → `anki/_assets/<slug>/`), `svg-knowledge-diagram` (inline SVGs per concept). The skill always *attempts* each; if a Day's content doesn't fit (e.g., no canonical Wikipedia concept), the call returns empty and we move on without failing.

## When to use

- Han drops a class transcript file (markdown from Notion export, Zoom transcription, etc.) in `_meta/` or similar staging area, plus optional screenshots from the session.
- Han says: "process Day-NN", "wrap Day-NN", "ingest class transcript", "tổng hợp transcript của buổi N".
- Han is in a learning track folder (`learning/<topic>/courses/<course>/`) and asks to process a buổi.

## When NOT to use

- Han asks a single "X là gì?" question outside of class-processing context → use `concept-explain`.
- Han drops general external material (docx, pdf, links) not from a class → use `ingest-to-wiki`.
- Han wants to update an existing Day-NN file (refinement, fix) → just edit directly.
- Han's source is not a class transcript (e.g. textbook chapter notes, paper read) → discuss what fits.

## Hard rules

1. **Adaptive structure for explained companion.** Follow `feedback_learning_tutoring_format` memory (v3 format): mandatory 5 sections + optional menu per concept. Do NOT use rigid 14-section template (v2 was anti-pattern; Han pushback).
2. **Prose-first, không bullet-heavy.** Diễn giải tiếng Việt là vehicle chính của hiểu. Bullets chỉ khi liệt kê 3+ items hoặc enumerate steps.
3. **Bilingual EN/VN selective.** Gloss tiếng Việt CHỈ cho term technical khó / lạ lần đầu xuất hiện. Term quen (P, NP, BQP, polynomial, qubit, algorithm): KHÔNG gloss. Tiếng Anh là nice-to-have, không essential.
4. **Cross-link only when natural.** Liên kết chuyên ngành (💼 SE / crypto / trading / ops / family-office) CHỈ khi thực sự illuminating. Drop khi gượng.
5. **Self-check + bài tập + đáp án always.** Mọi concept block có 🤔 self-check (2-3 câu, conceptual probe) + optional 🧮 Bài tập (math/operation exercises từ professor, extracted from transcript) + 🎓 đáp án (covers both). Han không phải tự đoán. Phân biệt: Self-check is comprehension probe (30s); Bài tập is actual operation (5-15 min). Skip 🧮 nếu transcript không có exercise cho concept đó.
6. **Workbook stays workbook.** Day-NN.md là cho Han-đã-fluent. Day-NN-explained.md là cho Han-mới (with bài tập). Day-NN-practice.ipynb là cho Han-đang-luyện (code + executable bài tập). Đừng trộn 3 file.
7. **Sources colocated.** Transcript + curated screenshots move vào `learning/<topic>/courses/<course>/sources/day-NN/`. Không để trong `_meta/`.
8. **Active collaboration.** Trong lúc viết, nếu thấy gì gợn (format hơi đặc, cross-link gượng, ví dụ yếu), propose inline cuối response. Đừng silent execute (per `feedback_propose_during_work`).
9. **No em-dashes (U+2014).** Per global formatting rule.
10. **RCSR loose coupling, not auto-trigger.** Day-NN.md frontmatter has `mermin_xref:` field when applicable (e.g. `QC-1`, `QC-2+`). DO NOT auto-create `workbooks/QC-N.md` từ Day-NN content; that's a Mermin deep-pass artifact with different scope. Day-NN-practice.ipynb covers the RCSR C-step (live code) but doesn't replace the R-step (read Mermin chapter) or S-step (write Mermin workbook). Two loops orthogonal; cross-ref only.
11. **Math notation: KaTeX `$...$`, NEVER backticks.** Inline math goes in `$...$`; display math in `$$...$$`. Han's vault has `obsidian-latex` plugin + vault-root `preamble.sty` with macros (`\ket`, `\bra`, `\braket`, `\dyad`, `\Tr`, `\E`, `\R`, `\C`, `\N`, `\Z`, `\HH`, `\tensor`). Use them. **Backticks render math as monospace literal text and skip KaTeX entirely** (anti-pattern observed in Day-04-explained.md). Reserve backticks for actual code identifiers (function names, file paths, commands). Examples: WRONG `` `P_i = α_i²` `` → RIGHT `$P_i = |\alpha_i|^2$`; WRONG `` `|+⟩ = (1/√2)|0⟩` `` → RIGHT `$\ket{+} = \frac{1}{\sqrt{2}}\ket{0}$`. See `feedback_learning_tutoring_format` Math notation section.

## Workflow

### Step 1: Detect inputs + identify track

Scan `_meta/` (or current cwd if other) for:

- **Transcript file**: markdown with timestamp pattern from Notion export (`@Yesterday`, `@Today`, datestamp + ID hex). 50KB+ usually means real transcript.
- **Screenshots**: PNG/JPG with timestamp pattern (CleanShot, Zoom screenshot, etc.).

Determine track + course from context:
- If cwd is inside `learning/<topic>/courses/<course>/`, use that.
- If `_meta/` material references a course (course name in transcript filename, in earlier messages), use that.
- If ambiguous, ask Han once: "Process this as Day-N of which course?"

Read `learning/<topic>/courses/<course>/syllabus.md` + the appropriate `Day-NN.md` stub to understand predicted content.

### Step 2: Locate prior context

Read in order:

1. `learning/<topic>/CLAUDE.md` (tutoring contract for the track).
2. `learning/<topic>/RCSR.md` or equivalent protocol doc.
3. `learning/<topic>/courses/<course>/syllabus.md` (predicted content per day).
4. `learning/<topic>/courses/<course>/Day-NN.md` (stub with predicted topics, time budget).
5. `learning/<topic>/courses/<course>/GLOSSARY.md` (existing concepts to avoid duplicate).
6. `learning/<topic>/docs/decisions/` (any ADRs that might affect scope).

Report what was found in 3-5 lines, then proceed.

### Step 3: Cross-check transcript vs prior expectations

Read transcript in chunks. Produce three buckets:

- **Đã học / consistent**: what matches prior stubs / syllabus.
- **Mới / new**: what's introduced for the first time, not in stubs.
- **Refinement / contradiction**: what sharpens or contradicts prior understanding (vd stub predicts 0.5h, actual is 1.5h).

This bucket list becomes a section in Day-NN.md.

### Step 4: Curate sources

Move + rename:

- Transcript: move to `learning/<topic>/courses/<course>/sources/day-NN/transcript.md`. Rename simply (`transcript.md`).
- Screenshots: review each. Keep ~5-7 with structural value (Venn diagrams, flow charts, key equations, summary slides). Delete rest. Rename kept ones by `slide-HH.MM-topic.png`.
- `rm -f` (not `rm`) to bypass any interactive `-i` alias.

Han approves which to keep if there are doubts (use AskUserQuestion). Han's working style allows silent deletion when there's clear precedent OR when the explicit ask is "keep only important ones".

### Step 5: Generate Day-NN.md (workbook)

Frontmatter (match existing Day-NN.md style in the course):

```yaml
---
day: <N>
date: <YYYY-MM-DD <weekday>>
status: done
track: <track_id>  # e.g. qbronze, qnickel, meta
time_budget: <actual hours>
session_title: <real lecture title from transcript>
instructor: <name>
---
```

Body sections (workbook density, for fluent reader):

1. **Cross-link to explained** at top: `> 🌱 Lần đầu đọc? Sang Day-NN-explained.md.`
2. **Session shape** table: predicted (stub) vs actual.
3. **Cross-check**: 3 buckets (đã học / mới / refinement).
4. **Hierarchical synthesis**: numbered sections matching transcript flow.
5. **Visuals timestamp index**: full N-slide table with file paths for kept screenshots, descriptions for those not kept.
6. **Open questions / transcript gaps**: anything unclear, name typos to flag, references to material not captured.
7. **Source**: paths to `sources/day-NN/`.

### Step 6: Generate Day-NN-explained.md (beginner companion)

Frontmatter:

```yaml
---
day: <N>
date: <date>
mode: explained
companion_of: Day-NN.md
practice_notebook: workbooks/Day-NN-practice.ipynb
audience: beginner re-reading transcript with ~20% prior understanding
format_version: 4
---
```

(`format_version: 4` reflects the bài tập + practice-notebook addition over v3.)

Body:

1. **Intro paragraph** explaining format adaptive + cross-link to workbook + practice notebook + GLOSSARY + transcript + slides.
2. **N concept blocks**, linear order following transcript flow. One block per major concept.
3. **Each block format**: mandatory (Định nghĩa as prose 1-2 đoạn, Why at first-principles, Ví dụ, 🤔 Self-check, 🧮 Bài tập if any in transcript, 🎓 Đáp án covering both), optional menu (Analogy, 📊 Diagram, 💼 Liên kết chuyên ngành, 🚨 Bẫy, 💡 Side note, 🔗 Cross-ref, ➡️ Đi tiếp).
4. **🧮 Bài tập extraction**: scan transcript for exercises professor explicitly assigned or worked on the board. Each exercise = verbatim statement + 5-15 min effort estimate. NOT comprehension probes (those are 🤔 Self-check).
5. **📊 Diagram embedding**: auto-invoke `svg-knowledge-diagram` skill for blocks whose payload fits one of the five archetypes (containment, growth, layered, pipeline, timeline). Save SVG to `assets/day-NN/<kebab>.svg` and embed via `![alt](../../../assets/day-NN/<kebab>.svg)` relative path. If no archetype fits cleanly, skip, don't force.
6. **Concept image embedding**: auto-invoke `concept-image-fetch` for blocks naming a canonical concept (Wikipedia coverage strong: Bloch sphere, Born rule, complexity-class Venn). Save to `anki/_assets/<concept-slug>/` per existing convention. Embed via `<img src="...">` for anki re-use. **Always pass an ABSOLUTE path** to `--download` (e.g. `--download /Users/tieubao/workspace/tieubao/ops-toolkit/learning/<topic>/anki/_assets`); relative paths land under the tool dir because `uv run --directory tools/concept-image-fetch` changes CWD.
7. **Tổng kết Day-N**: prose 2-3 takeaways chính (in đậm tên), then bullet list khái niệm nền touched, then forward-looking "Sang Day-(N+1)".

Quality bar: file is **900-1400 lines** for a 60-90 minute lecture (was 600-900 before bài tập + visuals). Less = sparse; more = bloat.

Reference memory for format details: `feedback_learning_tutoring_format`.

### Step 7: Generate Day-NN-practice.ipynb (executable practice notebook)

The RCSR C-step lives here. Jupyter notebook with mixed markdown + code cells.

**Always start from the template.** The track's `workbooks/_template/practice-notebook.py.tpl` is the source-of-truth shape. Copy it, fill `{{PLACEHOLDERS}}`, then add concept cells. Never hand-author the top banner / topics-details / bottom provenance cells from scratch — they're standardized so every notebook reads like a learning artifact (calibrated to QWorld OQI's `before-workshop.ipynb` polish, 2026-05-18).

**Mandatory shape** (per `workbooks/_template/README.md`):

1. **Top banner cell** (markdown, HTML-styled): orange-accent gradient div (`#E89412` accent), eyebrow subtitle (uppercase letter-spaced sans-serif: `<COURSE> · DAY <NN>`), serif H1 with the real lecture title, 2-3 sentence reader-facing intro ("Today you verify X, prove Y, and run Z"). No metadata. No file paths.
2. **Topics covered cell** (markdown, HTML-styled): collapsible `<details>` block, closed by default, with numbered list. Label `TOPICS COVERED` for C-step notebooks, `WHAT THIS NOTEBOOK PROVES` for popular-RSR verification notebooks.
3. **Setup cell** (code): imports (domain library + numpy + matplotlib), simulator init.
4. **Concept demo cells** (per concept block, paired markdown + code, plain `## Block N: ...` heading, no extra styling): each major concept gets a code cell that reproduces the lecture computation. E.g. Hadamard² = I → `H @ H == np.eye(2)` numerical verify + histogram plot.
5. **🧮 Bài tập cells** (per exercise, paired markdown + code): markdown cell with exercise statement; code cell with stub or solved version (Han's choice; default: provide stub + commented hint, separate solution cell hidden via collapse). For numerical exercises, include `assert` to verify expected output.
6. **"What to try next" cell** (markdown): variations Han can run, plus a `**Forward**:` one-liner previewing Day-(N+1).
7. **Bottom provenance cell** (markdown, HTML-styled): muted gray sidebar div with `NOTEBOOK PROVENANCE` eyebrow, then Date / Source / Flavor / Companions list. This is where metadata lives — never at the top.

**Don't deviate from the banner + provenance shape.** The styled cells are copy-paste from the template; only placeholder values change.

**Notebook conventions** (per SPEC-011):
- Path: `learning/<topic>/workbooks/<course>-day-NN.ipynb` (gitignored, build artifact) paired with `.py:percent` twin (committed source-of-truth).
- Pair on first creation: `uv run --with jupytext jupytext --set-formats ipynb,py:percent <file>.ipynb`. Edit either side; sync with `jupytext --sync <file>.ipynb` (auto-sync in JupyterLab once extension is loaded).
- Kernel: Python 3 default (Qiskit + Aer + matplotlib + jupyter installed per CLAUDE.md).
- Run nbconvert smoke test before commit: `uv run --with jupyter --with nbconvert --with qiskit --with qiskit-aer --with matplotlib jupyter nbconvert --to notebook --execute <file>.ipynb --output /tmp/test.ipynb`.
- **Hard rule** (per SPEC-011): edit the `.py` twin in Claude Code, not the `.ipynb`. The `.ipynb` JSON-blob is hostile to grep/diff/edit; the `.py:percent` form has cell markers (`# %%`) and is line-editable.
- Commit only `.py`. `.gitignore` enforces `*.ipynb` exclusion.

### Step 8: Update GLOSSARY.md

For each new concept introduced in this Day that has **cumulative cross-topic value** (not just course-specific), add an entry:

- Position alphabetically.
- Format: prose-first, same as Day-NN-explained block structure but standalone (no cross-refs to other blocks).
- End with `first seen: Day-NN`.

Skip concepts that are pure course-specific glossary (e.g. internal notebook ID like Q24 of QBronze).

### Step 9: Generate anki deck (TSV + .apkg) via `anki-builder`

Auto-invoke `anki-builder` skill at end of Day processing.

**TSV path**: `learning/<topic>/anki/<course>-day-NN.tsv` (e.g. `qworld-day-04.tsv`).

**TSV content** drawn from:
- Day-NN-explained.md concept blocks (Định nghĩa + Self-check + Đáp án → card content).
- GLOSSARY.md updates (new entries → basic-reversed cards for term ↔ definition).
- Concept-image-fetch results → image cards with `<img src="...">`.
- 🧮 Bài tập → numerical cloze or basic cards.

**Card model mix** per Day:
- `basic-reversed` for new term ↔ definition (5-10 per Day).
- `basic` for synthesis questions where one direction makes no sense (10-20 per Day).
- `cloze` for fact-dense statements / lists (2-5 per Day).
- Image cards (basic with `<img>` in front or back) for visual-anchored concepts (2-5 per Day).

**Deck path**: `Quantum::QWorld OQI::Day-NN` (or domain equivalent).

**Tags** per row: `qworld-oqi day-NN block-N <topic-tags>` (space-separated, kebab-case).

**Build command**:
```bash
uv run --directory tools/anki-builder anki-builder build \
    learning/<topic>/anki/<course>-day-NN.tsv \
    --asset-dir learning/<topic>/anki/_assets \
    --asset-dir learning/<topic>/courses/<course>/sources/day-NN
```

**Commit only the .tsv**, never the .apkg (per CLAUDE.md: "Source of truth is the TSV; `.apkg` is regenerated, never committed"). The skill's gitignore enforces this.

**Schedule preservation**: anki-builder uses stable GUIDs from front content. Editing back/extra/tags preserves Anki's spaced-repetition schedule for existing cards. Editing front creates new card; old card lingers until manual deletion.

### Step 10: Wrap-up report

Output to Han:

1. Paths to **4 artifacts**: Day-NN.md, Day-NN-explained.md, Day-NN-practice.ipynb, qworld-day-NN.tsv (+ note .apkg generated locally).
2. Line counts + cell counts + card counts.
3. List of sibling skills actually invoked + their outputs (e.g. "svg-knowledge-diagram fired 2 times, generating Hadamard-cancellation.svg + separable-vs-entangled.svg; concept-image-fetch fired 1 time, fetching bloch-sphere/0.png from Wikipedia").
4. **Propose 1-2 adjustments** if you noticed anything during writing (per `feedback_propose_during_work`). Examples: "I noticed the transcript had 4 names misspelled, flagged in Open Questions"; "Concept X feels load-bearing but stub didn't predict it; should we update syllabus?".
5. Forward look: "Day-(N+1) per syllabus will cover ...".

## Edge cases

- **Transcript references slides/figures not provided**: list in Open Questions. Don't fabricate visuals; ask Han to share if critical.
- **Multiple back-to-back classes in 1 day**: produce one `Day-N.md` per session, NOT combine. If same calendar day, use `Day-N-session-A.md` / `-session-B.md`.
- **Recording not yet posted**: Source section says "recording pending; YouTube link via Discord".
- **Auto-transcribe name typos**: standard. Flag in Open Questions section with corrections. Common: misspelled physicist names, mathematician names. Don't propagate typos into Day-NN-explained.
- **Math-heavy day with equations**: render LaTeX via `$...$` and `$$...$$` in markdown. VS Code Markdown Preview Enhanced renders cleanly. ASCII fallback only when math is trivial.
- **Code-heavy day (Jupyter notebooks referenced)**: don't reproduce code in explained file. Link to notebook path; explain pseudocode + concepts.
- **Han already started filling Day-NN.md stub**: respect his content, merge yours in. Don't overwrite.

## Anti-patterns (from session history)

1. **Rigid 14-section template**: was v2 format. Han pushed back as "lặp đi lặp lại cứng nhắc". Use adaptive v3.
2. **Emoji callouts on every micro-section**: noise. Use callouts to mark KEY sections (📊 Diagram, 🤔 Self-check, 🎓 Đáp án, 💼 Cross-link), but body is prose.
3. **Forced cross-links**: stretching to ép Turing machine link to family-office ops is noise. Skip cross-link when not natural.
4. **Bilingual gloss on every term**: overload. Gloss selectively.
5. **Bullet-list everything**: hard to read continuously. Prose paragraphs are vehicle of understanding.
6. **Silent execution**: per `feedback_propose_during_work`, surface adjustments inline.

## Reference

- Format contract: `~/.claude/projects/-Users-tieubao-workspace-tieubao-ops-toolkit/memory/feedback_learning_tutoring_format.md`
- Active collaboration mode: `~/.claude/projects/-Users-tieubao-workspace-tieubao-ops-toolkit/memory/feedback_propose_during_work.md`
- Reference output (Day-2 of QWorld OQI): `learning/quantum-computing/courses/qworld-oqi/Day-02.md` + `Day-02-explained.md` + `GLOSSARY.md`. Read for voice + length + adaptive shape, do not copy verbatim.
- Companion skill: `concept-explain` (for ad-hoc "X là gì?" questions outside class-processing).
