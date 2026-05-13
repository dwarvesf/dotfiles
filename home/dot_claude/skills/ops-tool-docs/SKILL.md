---
name: ops-tool-docs
description: |
  Write or refresh the doc CONTENT (README, MANUAL, RUNBOOK, SPEC, `docs/architecture.md`, per-feature SPECs under `docs/specs/`, ADRs under `docs/decisions/`) for a tool inside `~/workspace/tieubao/ops-toolkit/tools/`. Symptoms include "write the architecture doc for X", "this tool needs a manual", "document how X works", "explain the design decisions for X", "fill in the docs for X", "the housekeeper docs look great, write the same kind of docs for X", "X has no MANUAL.md, can you write one?", "I just finished X, write its docs". Reads the tool's existing code, `tool.toml`, entry-point, and tests to extract its real purpose, commands, dependencies, and host placement; then writes each missing doc FROM SCRATCH using audience-targeted intent. NOT a template fill: each tool's docs are shaped to that tool's reality. Calibration reference (read for voice + length, do not copy verbatim): `~/workspace/tieubao/ops-toolkit/tools/housekeeper/`. Pre-condition: the tool's folder layout is already correct. If not, hand off to the sibling skill `ops-tool-shape` first. NOT for structure changes (use `ops-tool-shape`), NOT for source-code edits, NOT for tools outside ops-toolkit.
---

# ops-tool-docs

This skill owns the **prose side** of the ops-toolkit tool standard: writing README, MANUAL, RUNBOOK, SPEC, architecture diagrams, per-feature SPECs, and ADRs. It assumes the folder structure is already correct; the sibling skill `ops-tool-shape` handles the file-presence side.

The canonical reference is `~/workspace/tieubao/ops-toolkit/tools/housekeeper/`. Read it to calibrate voice, density, and shape. **Do not copy from it.** The whole point of writing per-tool docs is to capture *that* tool's reality, not housekeeper's reality with names swapped.

## When to use

Fire on prose-side questions: how does this tool work, what's its manual, what should the architecture diagram say.

Trigger phrases:
- "write the architecture doc for X"
- "X needs a MANUAL"
- "document how X works"
- "explain the design decisions for X"
- "fill in the docs for X"
- "I just finished X, write its docs"
- "the housekeeper docs look great, do that for X"
- "what should the README say for X?"

Do NOT fire when the user is asking about structure:
- "what files does X need?" → `ops-tool-shape`
- "scaffold X" → `ops-tool-shape`
- "audit X's layout" → `ops-tool-shape`

Pre-flight before writing: confirm the tool's folder layout already matches `ops-tool-shape`'s requirements for its shape. If the layout is wrong, hand off to `ops-tool-shape` first. Examples of "layout wrong": MANUAL.md doesn't exist as a stub yet, or `docs/specs/` doesn't exist as a directory, or the tool has source files at the wrong path.

## Hard rules (the discipline this skill encodes)

1. **Read the tool first.** Before writing any doc, read its `README.md` (if any), `tool.toml`, entry-point script, key source modules, and tests. The docs must describe THIS tool's reality. Generic "this Python CLI sorts files" filler is the failure mode.
2. **No copy-paste from housekeeper.** Housekeeper is the calibration reference: read it for voice and length, never for words. If you find yourself typing "housekeeper" into a non-housekeeper doc, stop.
3. **One audience per doc.** README is for first-time visitors. MANUAL is for daily users. RUNBOOK is for operators-mid-incident. Do not mix audiences in one file. If you find content drifting to the wrong audience, move it.
4. **Match section count to reality.** Housekeeper MANUAL has 14 sections because it has 14 user-task types. A tool with one command does not get 14 sections; it gets one or two. Section count follows from content, not from a template.
5. **No ADRs without history.** Don't invent ADRs for tools with no design history worth recording. ADRs exist for *past decisions where alternatives were considered and one was picked for a reason*. A tool that was built straight from one idea has zero ADRs.
6. **Update INVENTORY.** Every doc-write closes a row's gap in `_meta/INVENTORY.md`. When all required files are present and non-empty, flip the tier to `done`.

## The doc set (audience and intent)

The five top-level doc files (README, MANUAL, RUNBOOK, SPEC, `docs/architecture.md`) plus the two sub-trees (`docs/specs/`, `docs/decisions/`). Each doc answers one question for one audience. **The audience-to-doc mapping is non-negotiable: don't mix audiences, don't duplicate intent. The file count is descriptive, not prescriptive: a one-feature tool's MANUAL might be three lines, its SPEC might live as a single tool-root `SPEC.md` instead of `docs/specs/SPEC-001-*.md`, and its `docs/architecture.md` might not exist at all. Match the tool's actual surface; refuse to force-fit the maximalist shape.**

The list below describes the *intent* of each artifact, not a checkbox to tick. If a tool's surface is small enough that one of these intents is already covered by the README, write a one-line note in SPEC.md acknowledging that and move on.

### README.md

**Audience:** first-time visitor. They've never seen this tool.
**Question:** what is this, and how do I install it?
**Voice:** marketing-precise. Confident, terse, no apology.
**Length:** one page. If you need more, link to MANUAL, RUNBOOK, SPEC, or `docs/`.
**Contains:**
- One-line description (what the tool does).
- One paragraph of context (why it exists).
- A "what's in this directory" link table to other docs.
- Install command(s) in a code block.
- A daily-use quick reference or a pointer to MANUAL.

**Anti-patterns:**
- Becomes the manual. If install + intro pushes past one screen, link to MANUAL.md instead of writing it here.
- Speculates about future features. README describes what exists now.
- Apologetic disclaimers ("this is a work in progress, I haven't tested it"). The tool either works or it doesn't.

### MANUAL.md

**Audience:** daily user. They installed the tool and want to do task X.
**Question:** how do I X?
**Voice:** task-oriented, copy-paste-able commands, sectioned by user task.
**Length:** as long as the tool's task surface is wide. One section per task. Each section: one-line intent + commands + expected output + one gotcha.
**Contains:**
- A table of contents at the top, linking to sections by task name.
- One section per task, in order of frequency-of-use.
- A "Gotcha" callout per section when there's one common stumble.
- Cross-links to RUNBOOK for incident scenarios.

**Anti-patterns:**
- Generic "how to use this tool" preamble. Cut. Go straight to the first task.
- Pad to match housekeeper's 14 sections. If the tool has 4 tasks, write 4 sections.
- Mix incident response in. If a section says "what to do when X breaks", move it to RUNBOOK and cross-link.

### RUNBOOK.md

**Audience:** operator in mid-incident. Something is wrong; they need to triage and fix.
**Question:** what do I do when the tool is broken?
**Voice:** triage-first. Symptoms → diagnosis → fix. Imperative.
**Length:** as long as the tool has plausible incidents. Often a daemon-service has 5-8 incident sections; a python-cli might have 1-2.
**Contains:**
- "First install / first-week probe" section if applicable.
- Common incidents, each with: symptom, how to detect, what's broken, fix command.
- "Where things live" table at the bottom: log paths, state files, config files.
- "Upgrade procedure" if non-trivial.

**Anti-patterns:**
- Becomes a how-to manual. Cross-link to MANUAL instead.
- Hypothetical incidents. Only list incidents you've actually seen or can clearly anticipate from the design.
- "Contact the author for help." This is the doc; write the fix.

### SPEC.md

**Audience:** anyone navigating the tool's docs.
**Question:** where do I find each document?
**Voice:** index. Bare links, short captions.
**Length:** ≤50 lines. If it grows past that, you're putting content in the wrong place.
**Contains:**
- A "Documents" table: file path | one-sentence purpose.
- A multi-feature roadmap (which features are in flight, planned, deferred) if the tool has more than one user-visible feature.
- Host placement (which machine the tool runs on, if a daemon).

**Anti-patterns:**
- Becomes the SPEC document itself (describing behaviour). Behaviour belongs in `docs/specs/SPEC-NNN-<feature>.md`. SPEC.md is just the navigator.
- Drift from reality. When MANUAL or RUNBOOK gets renamed, fix this table same commit.

### docs/architecture.md

**Audience:** new reader or future-self trying to understand the system.
**Question:** what does it look like in my head?
**Voice:** visual. ASCII diagrams with concise captions explaining what the diagram shows and what the takeaway is.
**Length:** as many diagrams as the tool has distinct components or flows. Three to six is typical. Each diagram + caption is its own section.
**Contains:**
- One diagram per question worth answering visually: "what hosts run what?", "what processes are alive?", "how does data flow through this tool?", "what's the decision tree at the LLM layer?", "what data leaves the box and what stays local?".
- ASCII only. Light-theme palette in the prose (avoid colored boxes; the user runs this in terminal + GitHub).
- A brief "Reader takeaway" line under each diagram saying what the reader should remember.

**Anti-patterns:**
- Diagrams that re-state what code shows. Skip if the architecture is one file calling one library.
- Stale diagrams. If the architecture changes, fix the diagram same commit as the code.
- Marketing diagrams that hide complexity. Show the failure modes, the fallback chains, the lock contention.

### Per-feature SPECs (`docs/specs/SPEC-NNN-<feature>.md`)

**Audience:** implementer reading the behaviour contract.
**Question:** what does feature X guarantee?
**Voice:** behaviour contract. Decision tables, schemas, verification commands.
**Contains (for each feature):**
- Context (why the feature exists).
- Architecture (the diagram for THIS feature, if different from the tool-wide one).
- Key decisions table (question | decision | rationale).
- Component design (one section per major module).
- Privacy / security boundary if the feature touches sensitive data.
- Verification table (test | command | expected).
- Out-of-scope list.

**Anti-patterns:**
- ONE giant SPEC.md at tool root for everything. Per-feature splits are the point.
- ADR-style WHY-only content. ADRs are separate; specs are WHAT-the-feature-does.

### ADRs (`docs/decisions/000N-<topic>.md`)

**Audience:** future architect (often future-you) trying to understand why a design choice was made.
**Question:** why did we build it this way?
**Voice:** historical. Context + decision + alternatives considered + trade-offs + open questions.
**Length:** ≤200 lines per ADR. If longer, you're probably mixing two decisions.
**Contains:**
- Status (proposed, accepted, superseded by NNNN).
- Date.
- Context (what state we were in when this decision was made).
- Decision (what we chose).
- Alternatives considered (what we rejected, why).
- Trade-offs (what we're giving up).
- Open questions (what we deferred).

**Anti-patterns:**
- Backfilling ADRs for decisions that didn't have alternatives. If there was no real choice, there's no ADR to write.
- ADRs as design documents. ADR is the record of WHY a decision was made, not the design itself.

## The RETROFIT workflow (existing tool, docs lag code)

This is the main workflow. The tool exists, its code works, but its docs are thin. Steps:

1. **Read the reality.** Open every file at the tool root + entry-point script + `tool.toml`. Skim tests if any. Note:
   - Tool name + one-line purpose.
   - Install steps (from existing README or install.sh).
   - Daily-use commands (from the CLI source or shell scripts).
   - Configuration knobs (env vars, sentinel files).
   - Host placement (Mini / Air / Cloud Worker).
   - Dependencies (Python deps from `pyproject.toml`, system deps from any README mentions).
   - Status (active, pilot, parked, abandoned).
2. **Determine shape.** From `ops-tool-shape`'s matrix. If unclear, ask the user.
3. **Check INVENTORY.** Read the row in `_meta/INVENTORY.md`. Confirm the gaps the audit identified.
4. **Decide which docs need writing.** Only the missing required ones, plus any optional ones the user explicitly asked for.
5. **For each doc, draft from the tool's reality.**
   - Sit with the tool's actual surface for a moment before writing.
   - Use the housekeeper doc of the same kind as a *voice* reference, not a *content* reference.
   - Resist filler. "This is a Python CLI" is filler; "Watches `~/Downloads` and moves files into `~/Documents/Inbox/` per a confidence threshold" is content.
6. **Sanity-check the rendered doc.**
   - No `housekeeper` mentions in a non-housekeeper doc.
   - No `{{placeholder}}` strings.
   - No claimed features the tool doesn't have.
   - Section count matches content density (not the calibration reference's count).
7. **Update INVENTORY.** Flip the per-file status from `MISSING`/`stub` to `✓`. When all required files for the shape are non-empty, flip the tier from `P0`/`P1`/`P2` to `done`. Add today's date in the notes column.

## Calibration snippets (VOICE ONLY, do NOT copy)

<!--
  CALIBRATION ONLY: read these to absorb voice + structure, NEVER copy.
  Every snippet below is verbatim housekeeper content. If you find yourself
  pasting any of it into a non-housekeeper doc, stop. The whole point of this
  skill is that each tool's docs describe THAT tool, not housekeeper with the
  name swapped.
-->

These are short illustrations of voice + shape. Read them, write fresh from each tool's reality.

### A good README opening (3 lines)

<!-- CALIBRATION ONLY: VOICE, NOT CONTENT. Do not paste into another tool's README. -->

```markdown
# housekeeper

Ambient macOS file-sorting agent. The runtime is designed to grow over time; the first feature is `housekeeper sort`, with `archive`, `dedupe`, `index`, `prune`, and `summarize` planned later.

> Day-to-day usage: [MANUAL.md](./MANUAL.md). Diagrams: [docs/architecture.md](./docs/architecture.md). Behavior contract: [docs/specs/SPEC-001-sort.md](./docs/specs/SPEC-001-sort.md). Incident recovery: [RUNBOOK.md](./RUNBOOK.md). Index: [SPEC.md](./SPEC.md).
```

Why this works: tool name as H1, one paragraph of confident context, no preamble, immediate link table to other docs.

### A good MANUAL section pattern (3 sections)

<!-- CALIBRATION ONLY: VOICE, NOT CONTENT. Do not paste into another tool's MANUAL. -->

```markdown
## 8. Undo a bad move

**What this does:** moves a file back to its original location, marks the row `undone_at`, and refuses safely if the file has drifted.

```bash
housekeeper log --limit 5
housekeeper undo 42
```

**Gotcha:** if iCloud Drive rewrote the path after the move, the sha check protects you but you'll have to file the file yourself.
```

Why this works: each section is one task, one-line intent, copy-paste-able commands, one gotcha. No padding.

### A good ADR opening (5 lines)

<!-- CALIBRATION ONLY: VOICE, NOT CONTENT. Do not paste into another tool's ADR. -->

```markdown
# ADR 0004: hybrid semantic routing with `Inbox/` + `Private/` fallback

**Date:** 2026-05-13
**Status:** accepted
**Supersedes:** an earlier type-bucket physical layout (`_sorted/<Type>/`, `_review/<category>/`) carried before this ADR.

## Context

An earlier draft moved every non-sensitive file into `~/Documents/_sorted/<Type>/` (six type buckets) and every sensitive file into `~/Documents/_review/<category>/`. The underscore-prefixed managed folders kept the design dumb-safe but cluttered `~/Documents/` with non-native-looking paths.
```

Why this works: sequence number + topic in the title, status block up top, context starts with "what state were we in before this decision" rather than "this ADR talks about...".

### A good architecture diagram (10 lines)

<!-- CALIBRATION ONLY: VOICE, NOT CONTENT. Do not paste into another tool's docs/architecture.md. -->

```
+-----------------+         +----------------+
|  fswatch event  |  --->   |  housekeeper   |
|  (~/Downloads/  |         |  sort <path>   |
|   ~/Documents/) |         |                |
+-----------------+         +--------+-------+
                                     |
                                     v
            +-----+ scope gate -----+
            |     | ignore gate
            v     | event-fresh gate
       skipped    | sha idempotency
                  v
              dispatcher -> {tier A | tier B | tier C}
```

**Reader takeaway:** events flow one direction; the gates fail-safe before any LLM is touched.

Why this works: ASCII only, light theme, labels are short, takeaway is one sentence and names what the diagram is FOR.

## Anti-patterns (what BAD doc-writing looks like)

- **Copy housekeeper docs, find-replace tool name.** The reader sees through this in two paragraphs. The tone is wrong, the examples don't apply, the gotchas don't match.
- **Pad to match a template's section count.** A tool with 3 user tasks does not get a 14-section MANUAL.
- **Mention features the tool doesn't have.** "Housekeeper supports `housekeeper archive` (coming soon)" is fine for housekeeper. "X supports archiving (coming soon)" for a tool that doesn't actually plan archiving is fabrication.
- **Write `docs/architecture.md` for a single-file tool.** If the architecture is "one script that does one thing", the README is enough. No diagram.
- **Backfill ADRs for tools with no decision history.** If you can't name what was rejected and why, the ADR shouldn't exist.
- **"This tool is a Python CLI."** Filler. Cut. Open with what the tool DOES.
- **Long preamble before getting to install/use.** README anti-pattern. The reader skipped to the code block; meet them there.

## Worked example: housekeeper's MANUAL (guided tour)

Read `~/workspace/tieubao/ops-toolkit/tools/housekeeper/MANUAL.md` and note:

- **§1 Install + first-day verification**: combines install commands with verification, because they're temporally adjacent for the user. One section, not two.
- **§2 Daily commands**: a table, not a tutorial. The user wants the command, not the lesson.
- **§3 Configure**: env vars + sentinels are different categories of knob but same audience (someone tuning the agent). Combined.
- **§7 Investigate a wrong classification**: gives the SQLite queries the user would actually run. Not "open the database and look around."
- **§8 Undo a bad move**: enumerates refusal cases. Every gotcha is named so the user knows what's normal vs broken.
- **§11 Reduce subscription burn**: has three sub-knobs (cap tuning, status watching, full-disable). Each is one paragraph. Tight.

The pattern: each section is one user task, with one-line intent, copy-paste-able commands, expected output, one gotcha. Replicate the pattern, not the content.

## After writing

When all required docs for the tool are present and non-empty:

1. Update the tool's row in `_meta/INVENTORY.md`. Tier moves to `done`. Add the date.
2. Tell the user the retrofit is complete. Mention any files you deliberately did not write (e.g., "skipped architecture.md because this is a one-script tool").
3. If you found anything about the tool that surprised you (a feature the docs didn't mention, a config knob the existing README missed), surface it explicitly so the user can confirm the doc is accurate.

If the tool is brand-new (just scaffolded), this is also the moment to flip `tool.toml#status` from `"pilot"` to whatever's right based on the docs you just wrote.
