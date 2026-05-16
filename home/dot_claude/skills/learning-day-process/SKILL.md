---
name: learning-day-process
description: Use when Han drops a class transcript (Notion export, recording transcription) + optional screenshots into `_meta/` or similar location, and wants the day's content processed into the learning track structure. Trigger phrases include "process Day-NN", "wrap Day-NN", "tổng hợp transcript Day-NN", "ingest class transcript", "tôi vừa add transcript của buổi học", "Day-N của <topic>", or any case where Han has dropped a raw class material and wants the standard workflow (cross-check vs prior expectations, generate workbook + beginner-explained companion, curate sources, grow glossary). Applies to all `learning/<topic>/` tracks in ops-toolkit: quantum, mathematics, security, etc. NOT for ad-hoc concept questions (use concept-explain). NOT for non-class content (use ingest-to-wiki for general material).
---

# Learning Day Process

Process a class transcript + screenshots into the standard 3-artifact output for any `learning/<topic>/` track in ops-toolkit. Output is reproducible: workbook (Day-NN.md) for the user-already-fluent reader, explained companion (Day-NN-explained.md) for the beginner reader, and incremental glossary update (GLOSSARY.md).

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
5. **Self-check + đáp án always.** Mọi concept block có 🤔 self-check (2-3 câu) + 🎓 đáp án ngay sau. Han không phải tự đoán.
6. **Workbook stays workbook.** Day-NN.md là cho Han-đã-fluent. Day-NN-explained.md là cho Han-mới. Đừng trộn 2 file.
7. **Sources colocated.** Transcript + curated screenshots move vào `learning/<topic>/courses/<course>/sources/day-NN/`. Không để trong `_meta/`.
8. **Active collaboration.** Trong lúc viết, nếu thấy gì gợn (format hơi đặc, cross-link gượng, ví dụ yếu), propose inline cuối response. Đừng silent execute (per `feedback_propose_during_work`).
9. **No em-dashes (U+2014).** Per global formatting rule.

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
audience: beginner re-reading transcript with ~20% prior understanding
format_version: 3
---
```

Body:

1. **Intro paragraph** explaining format adaptive + cross-link to workbook + GLOSSARY + transcript + slides.
2. **N concept blocks**, linear order following transcript flow. One block per major concept.
3. **Each block format**: mandatory (Định nghĩa as prose 1-2 đoạn, Why at first-principles, Ví dụ, 🤔 Self-check, 🎓 Đáp án), optional menu (Analogy, 📊 Diagram, 💼 Liên kết chuyên ngành, 🚨 Bẫy, 💡 Side note, 🔗 Cross-ref, ➡️ Đi tiếp).
4. **Tổng kết Day-N**: prose 2-3 takeaways chính (in đậm tên), then bullet list khái niệm nền touched, then forward-looking "Sang Day-(N+1)".

Quality bar: file is 600-900 lines for a 60-90 minute lecture. Less = sparse; more = bloat.

Reference memory for format details: `feedback_learning_tutoring_format`.

### Step 7: Update GLOSSARY.md

For each new concept introduced in this Day that has **cumulative cross-topic value** (not just course-specific), add an entry:

- Position alphabetically.
- Format: prose-first, same as Day-NN-explained block structure but standalone (no cross-refs to other blocks).
- End with `first seen: Day-NN`.

Skip concepts that are pure course-specific glossary (e.g. internal notebook ID like Q24 of QBronze).

### Step 8: Wrap-up report

Output to Han:

1. Paths to 3 files (workbook, explained, glossary update).
2. Line counts.
3. **Propose 1-2 adjustments** if you noticed anything during writing (per `feedback_propose_during_work`). Examples: "I noticed the transcript had 4 names misspelled, flagged in Open Questions"; "Concept X feels load-bearing but stub didn't predict it; should we update syllabus?".
4. Forward look: "Day-(N+1) per syllabus will cover ...".

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
