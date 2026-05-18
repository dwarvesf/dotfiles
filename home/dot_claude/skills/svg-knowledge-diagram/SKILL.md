---
name: svg-knowledge-diagram
description: Produce original SVG diagrams for knowledge-base notes and explanatory writing. Use this skill whenever creating visuals for technical or conceptual notes that will be pushed to a knowledge repo, embedded in markdown, or shown alongside an explanation. Trigger this skill when the user asks for a concept diagram, comparison chart, history timeline, layered explanation visual, or any "I'm a visual learner, draw it for me" moment. Also trigger when the user asks to capture conversation content with visuals, when web-scraped images would be a copyright risk, or when the task is to illustrate a concept the user is actively learning. Ships an inline `learning` palette (indigo + rose); optionally pairs with a `visual-design` skill (for broader palette tokens) and `knowledge-capture` (for the broader note workflow). For photorealistic hero/scene images, use `image-spec` instead.
---

# SVG Knowledge Diagram

A pattern library for producing **explanatory SVG diagrams** that hold up as standalone learning material. Originally extracted from a set of quantum-computing concept diagrams that the user judged "very good" enough to want repeatable.

This skill is about diagrams that **teach**, not diagrams that decorate. Every diagram should be readable on its own (without the surrounding prose) and should encode a specific cognitive payload: a containment relationship, a growth comparison, a process flow, a side-by-side, or a timeline.

## When to use

- The user is learning a concept and wants a visual that anchors the explanation.
- A note will be pushed to a knowledge repo and needs an embedded image.
- The alternative is scraping copyrighted thumbnails (textbooks, slide decks, blogs), generate originals instead.
- A comparison or hierarchy is dense enough that prose alone overflows working memory.

## When NOT to use

- Hand-drawn intuition that fits in 1-2 sentences. Don't draw what a clear sentence already does.
- Data visualization with real numbers. Use a chart skill or a charting library for that.
- UI mockups or product screens. Use `frontend-design` for that.
- When the user explicitly says "skip the visuals, just push the prose."

## Palette tokens (self-contained)

This skill ships an inline minimal palette for the `learning` context so it can stand alone. If a `visual-design` skill is available with broader palettes (work / dwarves / wealth / family / learning), read it first and override the table below. Otherwise use these.

### Learning palette (indigo + rose, the quantum-notes default)

| Token | Hex | Role |
|---|---|---|
| `bg` | `#FAFAFB` | background |
| `text` | `#1E1B4B` | primary text (dark indigo) |
| `text-muted` | `#4B5563` | secondary text |
| `text-axis` | `#9CA3AF` | axis labels, annotations |
| `primary-100` | `#EEF2FF` | takeaway-band fill, table header tint |
| `primary-200` | `#A5B4FC` | takeaway-band stroke, card borders |
| `primary-500` | `#6366F1` | curves, ellipses, fills |
| `primary-700` | `#3730A3` | titles, accent bars, arrow markers |
| `primary-900` | `#1E1B4B` | main title text |
| `secondary-500` | `#E11D48` | breakthrough / contrast / "the surprising one" (rose) |
| `secondary-700` | `#9F1239` | rose-on-card accent bar |
| `secondary-100` | `#FFE4E6` | rose tint fills |
| `secondary-200` | `#F4A0A0` | rose card border |
| `warning-100` | `#FEF3C7` | amber/caveat panel fill |
| `warning-500` | `#D97706` | amber border, "the catch" |
| `warning-900` | `#92400E` | amber text |
| `danger-100` | `#FEE2E2` | red bottleneck-cell tint |
| `danger-700` | `#DC2626` | red bottleneck text |
| `card-stroke` | `#E5E7EB` | thin gray card borders, table dividers |

**Semantic rule.** Indigo = standard/default. Rose = breakthrough/contrast/danger. Amber = caveats/"the catch". Gray = annotations. Never decorative; if a node is rose, the diagram should answer "why is that one different?"

For other contexts (work, wealth, family, dwarves) the user's quantum notes don't yet have canonical hex tokens. Ask before drawing for those contexts, or default to substituting the primary hue while keeping the structural rules.

## The five diagram archetypes

Match the diagram archetype to the conceptual payload. Most knowledge content slots into one of these five.

| Archetype | Use when | Reference example |
|---|---|---|
| **Containment / Venn** | Showing how one set sits inside another, especially with "open question" relationships | `complexity-classes-containment.svg` |
| **Growth comparison** | Showing how two regimes diverge at scale (polynomial vs exponential, linear vs log, etc.) | `polynomial-vs-exponential.svg` |
| **Layered concept** | Breaking down a multi-stage idea (① classical baseline → ② new mechanism → ③ caveat → ④ takeaway) | `superposition-and-interference.svg` |
| **Process / pipeline comparison** | Showing how different instances of the same skeleton fill in differently | `state-preparation-comparison.svg` |
| **Timeline** | Plotting the chronology of breakthroughs in a field, with patterns called out at the bottom | `quantum-algorithms-timeline.svg` |

Detailed templates and examples for each are in `references/archetypes.md`.

## Core design rules

These rules came out of what made the quantum SVGs work. Follow them by default; deviate only with a reason.

### 1. One title, one subtitle, always

```xml
<text x="500" y="40" text-anchor="middle" font-size="20" font-weight="700" fill="#1E1B4B">Main Title</text>
<text x="500" y="62" text-anchor="middle" font-size="12" font-weight="400" fill="#4B5563">A one-line cognitive payload, what should the viewer learn?</text>
```

The subtitle is not decoration. It states the single takeaway. If you can't write the subtitle in one sentence, your diagram is doing too much.

### 2. End with a takeaway band

Every diagram ends with a horizontal band near the bottom containing the **one sentence to remember**. This is what survives if the viewer only glances:

```xml
<rect x="80" y="555" width="840" height="32" rx="6" fill="#EEF2FF" stroke="#A5B4FC" stroke-width="1" stroke-dasharray="6,3"/>
<text x="500" y="575" text-anchor="middle" font-size="11" font-weight="600" fill="#3730A3">The single sentence to remember.</text>
```

The dashed border signals "this is a note, not a primary element."

### 3. Annotations, not labels

Inside the diagram, points are connected to small annotation cards with a dashed line:

```xml
<line x1="290" y1="280" x2="220" y2="200" stroke="#9CA3AF" stroke-width="1" stroke-dasharray="4,3"/>
<rect x="100" y="170" width="180" height="50" rx="6" fill="white" stroke="#A5B4FC" stroke-width="1.2"/>
<rect x="100" y="170" width="180" height="3" fill="#3730A3"/>
<text x="190" y="190" text-anchor="middle" font-size="11" font-weight="700">Annotation title</text>
<text x="190" y="207" text-anchor="middle" font-size="9" fill="#4B5563">supporting detail</text>
```

Annotation cards always have a 3px top accent bar in the primary color (the same card pattern used in the worked-example archetypes below).

### 4. Color = semantic meaning, not decoration

In the learning palette:
- **Indigo (primary)** = standard, default, "expected"
- **Rose (secondary)** = breakthrough, danger, the surprising element, the warning
- **Neutral gray** = annotations, axis labels, supporting detail
- **Amber (extended)** = caveats, "wait, here's the catch" callouts

Don't paint things just to make them colorful. If a node is rose, the viewer should ask "why is that one different?" and the diagram should answer.

### 5. Light theme, hardcoded hex

Always. No CSS variables (the SVGs go to R2 and GitHub raw and must render anywhere). Background `#FAFAFB`. Text dark indigo on white. This matches the user's `Visual preference: light theme for all diagrams, hardcoded hex (no CSS variables)` rule from memory.

### 6. Drop-shadow filter, used sparingly

```xml
<defs>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="1" stdDeviation="3" flood-opacity="0.08"/>
  </filter>
</defs>
```

Apply only to cards that need to lift off the background. Not to every element, that defeats the purpose.

### 7. Viewbox proportions

- Wide comparison / timeline: `viewBox="0 0 1000 600"` or `1100 600`
- Tall layered concept: `viewBox="0 0 1000 720"`
- Containment / Venn: `viewBox="0 0 1000 600"`

Aim for an aspect ratio close to 5:3 unless you have a reason to go taller. Most markdown viewers render this well.

## Workflow

0. **Gather context first.** Read `references/context-gathering.md` and run the 5-element checklist:
   - [ ] Cognitive payload (one sentence, the diagram's thesis)
   - [ ] Archetype match (one of the five)
   - [ ] 2-3 concrete anchors
   - [ ] Palette context (from the inline table above, or `visual-design` skill if present)
   - [ ] Surrounding prose context (if any)

   If 2+ elements are missing or guessed → batch the questions and elicit before drafting. If 0-1 missing → name your assumption inline and proceed. Never elicit context that's already obvious from the conversation.

1. **Commit to an archetype.** Match the cognitive payload to one of the five. If nothing fits cleanly, the content may not be ready for a diagram, write the prose first.
2. **Confirm the palette.** Use the inline `learning` palette unless a `visual-design` skill is available and the context isn't learning.
3. **Read `references/archetypes.md`.** Use the template that matches your archetype.
4. **Draft the SVG.** Title + subtitle first, then content, then takeaway band last. The subtitle should be the cognitive payload from Step 0 verbatim or near-verbatim.
5. **Save to a working dir.** Pick one of:
   - **Direct-commit (preferred when you know the consumer repo):** `<repo>/assets/<topic>/<kebab-name>.svg`. The til quantum batch uses `til/assets/notes-quantum/`. Skip Step 6 entirely; embed via repo-relative or GitHub-raw URL.
   - **Local working dir (when uploading to an asset host):** `/tmp/svgs/<kebab-name>.svg` on Claude Code, `/home/claude/svgs/` on Claude.ai sandbox. Then proceed to Step 6.
6. **(Optional) Upload to an asset host.** Only if hosting separately from the consumer repo. See `references/r2-upload.md` for the user's R2 worker recipe (host + token are parameterized).
7. **Embed in markdown** with the resulting URL or relative path.

The full chain is: **context → archetype → draft → save → embed**. Upload is optional. Skipping Step 0 is the single most common cause of mediocre output.

## File outputs and embedding

Two valid output modes:

### Mode A: direct-commit to consumer repo (recommended for til)

Save the SVG to `<repo>/assets/<topic-or-source-slug>/<kebab-name>.svg`. Embed via repo-relative path or GitHub-raw URL:

```markdown
![Description for accessibility](../../assets/notes-quantum/diagram-name.svg)
```

or

```markdown
![Description for accessibility](https://raw.githubusercontent.com/<user>/<repo>/main/assets/notes-quantum/diagram-name.svg)
```

Pros: no auth, no asset-host dependency, history travels with the note. Cons: SVGs in the repo bloat clone size if the count grows past ~100.

### Mode B: upload to an external asset host

After uploading (see `references/r2-upload.md`), the URL is whatever your host returns. The user's existing R2 worker returns:

```markdown
![Description for accessibility](https://assets.han-ws.workers.dev/i/YYYY/MM/diagram-name.svg)
```

Pros: keeps the repo lean, CDN-cached. Cons: requires a token and a worker, breaks if the asset host moves.

## Pairing with other skills

- **`visual-design`** (optional): if a richer palette system exists (work / dwarves / wealth / family / learning), read it and override the inline `learning` palette. If absent, the inline palette is sufficient.
- **`knowledge-capture`**: this skill produces the visuals; knowledge-capture produces the notes that embed them. Often called in the same workflow.
- **`image-spec`**: the sibling for photorealistic hero / place / scene images. Route place-of-Da-Lat to `image-spec`, route BQP-Venn-diagram here.
- **`twitter-capture`, `youtube-capture`, `reel-transcript`**: capture skills that may benefit from a generated diagram if the source content is conceptual.

## Anti-patterns

- **Skipping Step 0.** The biggest quality killer. Diagrams produced without explicit cognitive payload, archetype, and anchors are pretty but don't teach.
- **Eliciting context that's already in the conversation.** Frustrating to the user. If the topic is obvious, the palette is obvious, and the anchors are named, just proceed.
- **Inferring an archetype when the payload is ambiguous.** Wrong-shaped diagrams need to be redone. If you're stuck between two, ask in one sentence.
- **No subtitle.** Diagrams without a one-line cognitive payload are decoration.
- **No takeaway band.** If the viewer only glances, what should they walk away with?
- **Color salad.** Using 4+ hues in a diagram without a strong reason. Stick to primary + one accent.
- **Trying to fit two archetypes in one SVG.** Split into two diagrams. The user can embed both.
- **Decorative drop-shadow on everything.** Defeats the purpose.
- **CSS variables.** They will break on GitHub raw and on R2.
- **Tiny text under 8px.** Unreadable on most rendering targets.
- **Ignoring the surrounding prose.** A diagram dropped into a note without reading the note tends to either repeat what the prose says or contradict it.

## References

- `references/context-gathering.md`, the 5-element pre-SVG checklist. Read first.
- `references/archetypes.md`, templates and worked examples for the five archetypes.
- `references/r2-upload.md`, curl command for uploading to the user's R2 assets worker. May need to be substituted with a different upload destination for other users.
- `references/quantum-svgs-as-examples.md`, the five original quantum SVGs, annotated with what made them work.
