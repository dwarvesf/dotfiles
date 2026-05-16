---
name: ops-tool-shape
description: |
  Verify or set up the file and folder structure of a tool under `~/workspace/tieubao/ops-toolkit/tools/`. Use when scaffolding a brand-new tool, restructuring an existing tool to match the standard, or auditing which doc files a tool currently has vs needs. Symptoms include "scaffold a new ops-toolkit tool", "audit <tool>'s structure", "what files does <tool> need?", "is <tool>'s layout compliant?", "set up the folder for a new tool", "what's missing from <tool>?", "the tide structure looks great, what shape should <X> be?". Outputs a tool directory with the right folder layout (empty stubs only; no doc content), plus a row update in `ops-toolkit/_meta/INVENTORY.md`. After this skill finishes, the sibling skill `ops-tool-docs` fills in the doc content. Canonical reference (read it, don't copy it): `~/workspace/tieubao/ops-toolkit/tools/tide/`. NOT for writing doc CONTENT (that's `ops-tool-docs`), NOT for tools outside ops-toolkit, NOT for `experiments/<slug>/` (those follow a different gradient), NOT for third-party-tool deploy bundles where upstream owns the docs.
---

# ops-tool-shape

This skill owns the **structural side** of the ops-toolkit tool standard: which files live where, which files are required for which kind of tool, and how `_meta/INVENTORY.md` tracks the current state. It does not write doc content. When the structure is right, hand off to `ops-tool-docs` to fill in prose.

The canonical reference instance is `~/workspace/tieubao/ops-toolkit/tools/tide/`. Read it for the actual shape; do not copy filenames out of it. (Housekeeper was the canonical reference until its 2026-05-14 deletion; tide inherited the doc shape unchanged. The calibration target is the same.)

## When to use

Fire when the user is asking a **structural** question: which files should this tool have, what shape is this, what's the layout, what's missing.

Fire on phrases like:
- "scaffold a new ops-toolkit tool called X"
- "set up the folder for X"
- "audit X's structure"
- "what files is X missing?"
- "is X's layout compliant with our standard?"
- "the tide folder shape looks right, apply that to X"

Do **not** fire when the user is asking about content:
- "write the README for X" → `ops-tool-docs`
- "explain how X works" → `ops-tool-docs`
- "fill in the manual for X" → `ops-tool-docs`

Do **not** fire outside ops-toolkit. This skill is scoped to `~/workspace/tieubao/ops-toolkit/tools/`. For `experiments/<slug>/`, the gradient is different (a `README.md` with frontmatter is enough; see `experiments/README.md`).

## Inputs the skill needs

Ask for these at the start. If any are missing, ask before scaffolding or auditing.

| Input | Example | Required for |
|---|---|---|
| Tool name | `tide` (kebab-case) | scaffold |
| Tool path | `~/workspace/tieubao/ops-toolkit/tools/<name>/` | audit |
| Tool shape | `simple-shell-tool`, `simple-script-tool`, `python-cli`, `shell-tool`, `substrate-tool`, `daemon-service`, `deploy-bundle`, `docs-only`, `mixed` | both |
| One-line description | what the tool does | scaffold |
| Consumers | which downstream repos consume it (often `[]` for personal) | scaffold |

If shape is unclear, look at the tool's code (or planned code) and pick from the table below. Ask the user to confirm if more than one shape could apply.

## The folder layout

The canonical tree. Files marked `(*)` are required for every tool; others are required only for some shapes (see matrix below).

```
tools/<name>/
├── README.md                          (*) one-page intro + install + links
├── MANUAL.md                              task-oriented "how do I X?"
├── RUNBOOK.md                             incident response
├── SPEC.md                                top-level index
├── tool.toml                          (*) ops-toolkit registration per _meta/SCHEMAS.md
├── pyproject.toml                         if Python
├── .gitignore                             tool-specific ignores
├── .envrc.example                         op:// refs for secrets
├── docs/
│   ├── architecture.md                    ASCII diagrams (or STACK.md for substrate)
│   ├── specs/SPEC-NNN-<feature>.md        per-feature behaviour contracts
│   ├── decisions/000N-<topic>.md          ADRs
│   └── runbooks/                          optional, tier-specific runbooks
├── src/<name>/                            Python package (if Python)
├── tests/                                 if there are tests
└── deploy/macos/                          LaunchAgent artifacts (if daemon)
```

Files at the tool root are user-facing entry points. Files under `docs/` are detail. Files under `src/`, `tests/`, `deploy/` are implementation.

The structural **intent** is non-negotiable: one audience per file, predictable file names, no duplicating-the-canonical-reference-with-find-replace. The **file count** is descriptive, not prescriptive: match the tool's actual surface. A one-feature tool does not get a 7-file doc set just because the matrix maximalist row lists 7 entries. Each row below describes the SHAPE the tool can grow into; tools start at the small end and graduate.

## Tool shapes (which files are required)

The shape determines which optional files become required.

| Shape | README | MANUAL | RUNBOOK | SPEC | docs/arch | docs/specs/ | docs/decisions/ | tool.toml |
|---|---|---|---|---|---|---|---|---|
| `simple-shell-tool` (one shell script at tool root, no install dance) | ✓ | – | – | opt | opt | opt | opt | ✓ |
| `simple-script-tool` (one short script at tool root in any language, e.g. `vn-invoice/vn_invoice.py`, `notion-ops/*.py`) | ✓ | – | – | opt | opt | opt | opt | ✓ |
| `python-cli` (Python package with a CLI, like `annas-fetch`, `tg-cleanup`) | ✓ | ✓ | – | ✓ | opt | opt | if-hist | ✓ |
| `shell-tool` (multi-script shell tool with operational surface, like `mac-backup`, `llm-bench`) | ✓ | opt | ✓ | ✓ | opt | opt | opt | ✓ |
| `substrate-tool` (host-substrate: STACK.md + multi-doc tree at tool root, like `mac-mini-substrate`, `mac-laptop-substrate`) | ✓ | – | opt | opt | use STACK.md | opt | opt | ✓ |
| `daemon-service` (LaunchAgent / long-running process, like `tide`, `notion-export`; **canonical reference is `tide`**: daemon + CLI + multi-feature roadmap, every required + optional file populated) | ✓ | ✓ | ✓ | ✓ | opt-until-multi | opt-until-multi | opt-until-multi | ✓ |
| `deploy-bundle` (a `*-deploy/` recipe for a third-party tool, like `writebook-deploy`, `apfel-deploy`) | ✓ | – | ✓ | opt | – | opt | opt | ✓ |
| `docs-only` (a recipe / explainer with no executable code, like `agentic-inbox`) | ✓ | – | – | – | – | – | – | ✓ |
| `mixed` (rare; multi-language tool with substantial structure, like `hermes`, `vps-mon`) | ✓ | ✓ | ✓ | ✓ | opt-until-multi | ✓ | opt-until-multi | ✓ |

Legend: `✓` required, `–` not applicable, `opt` write only if the tool has content for it, `opt-until-multi` optional while the tool has ≤1 feature; promote to required when adding the 2nd feature, `if-hist` write only if there's design history worth recording.

### Accepted deviations (do NOT force-fix these)

- **`STACK.md`** substitutes for `docs/architecture.md` in `substrate-tool` shapes (`mac-mini-substrate`, `mac-laptop-substrate`). The topology IS the architecture for that domain. Other substrate-flavored docs (e.g. `access-status.md`, `rebuild-runbook.md`, dotfiles drafts) live at the tool root, not under `docs/`, because substrate tools predate the `docs/` convention.
- **Flat `specs/` at tool root** (e.g. `annas-fetch/specs/PLAN.md` + `specs/NN-*.md`) instead of `docs/specs/SPEC-NNN-*.md`. Predates the multi-spec convention; acceptable to leave in place. New tools should adopt `docs/specs/`.
- **Cross-tool SPEC numbering** (e.g. `mac-backup/SPEC-042-offsite-l4.md`) for shared namespaces with sibling repos.
- **Tool-internal SPEC numbering** (`hermes`, `vps-mon`, `openclaw`) when a tool has 5+ features and grew its own numbering scheme.
- **Compressed-doc shells**: a `simple-shell-tool` or `simple-script-tool` can collapse README + a brief HOW-TO section into a single README.
- **One-feature daemons skip `docs/`.** A `daemon-service` with one cron + one script (like `notion-export`) is done at README + MANUAL + RUNBOOK + SPEC at tool root. Promote to `docs/specs/` + `docs/architecture.md` + `docs/decisions/` only when a 2nd feature lands or the tool's design history grows past one ADR worth of context.
- **Parked tools** (`status = "parked"` in `tool.toml`) get only README + tool.toml. They're frozen; don't write MANUAL/SPEC for them.

If you see one of these patterns, recognize it and leave it alone. The standard adapts to the tool.

## Two workflows

### Workflow 1: SCAFFOLD (new tool)

User has named a new tool and wants the folder set up.

1. **Confirm inputs.** Tool name, shape, one-line description, consumers. Ask if anything is missing.
2. **Create the directory tree.** `mkdir -p ~/workspace/tieubao/ops-toolkit/tools/<name>/{docs/{specs,decisions,runbooks},src/<name>,tests}` plus `deploy/macos/` if the shape calls for it. Pythonic tools get `src/<name>/__init__.py` as an empty file.
3. **Create empty file stubs.** For each file the shape requires, create the file with one line: `# <title>` plus a `<!-- TODO(ops-tool-docs): fill content -->` comment. Do NOT write content; that's `ops-tool-docs`.
4. **Write a minimal `tool.toml`** with the fields from `_meta/SCHEMAS.md`: name, description, language, status (start at `"pilot"`), entry (if known), created (today), consumers, systems (empty if unknown), secrets (empty), depends_on (empty).
5. **Add `.gitignore`** scoped to the tool (Python builds + the SQLite/log artifacts the tool will produce). Steal from `tools/tide/.gitignore` if Python.
6. **Update `_meta/INVENTORY.md`.** Add a new row for the tool. Tier starts at `P1` (structure exists, docs are empty). One column per file in the layout, marked `stub` for newly-created empty files.
7. **Update `MANIFEST.md`** (at the repo root, not `_meta/`). Add the tool row per the existing format. Wire `tool.toml#consumers` and the consumer repos' `.ops-toolkit/link.toml#uses` together.
8. **Tell the user what comes next.** "Structure is ready. Run `ops-tool-docs` (or ask Claude to 'write the docs for `<name>`') to fill in content."

Do NOT run any tests, install scripts, or external commands during scaffold. Structure is a pure filesystem operation.

### Workflow 2: AUDIT (existing tool)

User wants to know what an existing tool is missing.

1. **Read the tool directory.** `ls -la tools/<name>/` and `ls tools/<name>/docs/` (if it exists). List every file present.
2. **Determine shape.** From the matrix above. If unclear, look at the entry point and `tool.toml`. If still unclear, ask the user.
3. **Compute the gap.** Compare present files against shape's required set. Note also: are there intentional deviations to respect? (`STACK.md` instead of `architecture.md` for substrate; tool-internal SPEC numbering for mature tools.)
4. **Emit a gap report.** Plain prose: "X has README + tool.toml + 2 deploy plists. Missing for `daemon-service` shape: MANUAL, RUNBOOK, SPEC, docs/architecture.md." Honest about deviations: "Accept this tool's existing SPEC-NNN numbering."
5. **Update or insert the INVENTORY row.** Mark per-file status (`✓` present, `–` not required for shape, `stub` if file exists but empty, `MISSING` if required and absent). Set tier:
    - `done`: all required files present with non-empty content.
    - `P0`: README is missing.
    - `P1`: README present plus ≤1 other required doc artifact.
    - `P2`: README plus ≥2 other doc artifacts, but ≥1 required doc still missing.
    - `P3`: mature tool with intentional deviations; accept as-is.
6. **Tell the user what comes next.** "Audit complete. <N> files missing. Hand off to `ops-tool-docs` to write the missing prose."

The audit does NOT create or modify any files in the tool itself. It only updates `_meta/INVENTORY.md`.

## How the two skills coordinate

```
+-------------------------+         +-------------------------+
|  ops-tool-shape (this)  |  ---->  |  ops-tool-docs          |
|  - folder layout        |         |  - audience-doc intent  |
|  - file presence        |         |  - voice + length       |
|  - INVENTORY tier       |         |  - retrofit workflow    |
|  - SCAFFOLD + AUDIT     |         |  - calibration snippets |
+-------------------------+         +-------------------------+
            \\                                  //
             v                                  v
        +-----------------------------------------+
        |  ops-toolkit/_meta/INVENTORY.md         |
        |  Shared bridge. This skill creates +    |
        |  updates rows; ops-tool-docs flips      |
        |  tier to `done` when prose lands.       |
        +-----------------------------------------+
```

Brand-new tool: this skill first, then `ops-tool-docs`. Existing tool missing only prose: skip directly to `ops-tool-docs`. Existing tool with broken structure (rare): this skill first to fix the layout, then `ops-tool-docs`.

## Anti-patterns

- **Force-fitting a shape.** A `simple-shell-tool` does not need MANUAL just because the standard mentions it. Read the matrix; respect the optional / not-applicable cells.
- **Creating source files.** This skill is structure-only. Never write `.py`, `.ts`, `.sh`, or other code. If the user asks for code scaffolding, that's a different conversation.
- **Rewriting intentional deviations.** `hermes/docs/specs/SPEC-NNN-*.md`, `vps-mon`'s 19-spec numbering, `mac-mini-substrate/STACK.md`: these are correct for their tools. Leaving them alone is the right move.
- **Leaving per-feature SPECs at tool root.** A `SPEC-<feature>.md` file at the tool root is wrong even if there is only one of them. Tool-root `SPEC.md` is the **index** only. Per-feature behaviour contracts always live under `docs/specs/`. (An earlier housekeeper-era ADR floated "OK for ≤3 specs" as a build-time observation for `mac-backup`'s pre-standard layout; it was never a general accepted-deviation and the ADR is gone with housekeeper.) New tools and existing tools being touched should use `docs/specs/` regardless of feature count. If a tool's per-feature spec sits at root, move it: `git mv tools/<x>/SPEC-foo.md tools/<x>/docs/specs/SPEC-foo.md` and update cross-references.
- **Writing prose into stubs.** A stub is a one-line file with a TODO marker. Filling in `## Install` instructions belongs to `ops-tool-docs`. Resist.
- **Modifying the canonical reference.** `tools/tide/` is the live calibration instance. Do not edit it as part of scaffold or audit.

## Worked example: tide

This is the shape this skill teaches. Read each file for what it accomplishes:

| Path | What this file is |
|---|---|
| `README.md` | One-page intro: what is tide, install command, links to MANUAL/RUNBOOK/SPEC. |
| `MANUAL.md` | Task guide ("how do I bootstrap a pile?", "how do I undo a move?", "how do I disable Tier B?"). |
| `RUNBOOK.md` | Incident manual (LaunchAgent crash-loops, TCC blockers, sensitive false positives, runaway-tick incident playbook). |
| `SPEC.md` | Index: a table linking the other docs + multi-feature roadmap. |
| `SKILL.md` | Tool-specific anomaly: tide ships its own SKILL.md at root because the LaunchAgent invokes `claude --append-system-prompt-file SKILL.md ...`. Not a general requirement; included here so you don't mistake it for "every tool needs a SKILL.md". |
| `docs/architecture.md` | ASCII diagrams + reader-takeaway captions. |
| `docs/specs/SPEC-001-bootstrap-flow.md` | The bootstrap feature's behaviour contract (top-level vs recursive, curation heuristics). |
| `docs/specs/SPEC-002-watch-flow.md` | The watch-tick feature's behaviour contract (10-min poll, null-watermark guard, candidate enumeration). |
| `docs/specs/SPEC-003-sensitivity-cascade.md` | Tier A/B/C routing contract. |
| `docs/specs/SPEC-004-planner-judge.md` | Roadmap doc (carried from housekeeper; not yet adapted). |
| `docs/decisions/0001-claude-code-as-ambient-executor.md` ... `0004-...md` | ADRs sequenced by build order; explain WHY. |
| `tool.toml` | ops-toolkit registration with consumers, systems, secrets. |
| `pyproject.toml` | uv-managed Python. |
| `deploy/macos/mini.tide.plist` | LaunchAgent definition. |
| `deploy/macos/install.sh`, `uninstall.sh` | Bootstrap + teardown. |
| `op-env.template` | `op://` references for the LaunchAgent's `op run --env-file` invocation. |

Note what the layout enables: a user with one question goes to one file. Each artifact serves a single audience. That's the whole point of the structure rule: pointing a reader at the right file is the value, not the file count.
