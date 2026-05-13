---
name: image-spec
description: |
  Use when the user wants to generate per-image specifications (prompts + structured knobs) for AI image generation (nano-banana / Gemini 2.5 Flash Image, Imagen, Midjourney, Stable Diffusion) to support a set of markdown documents. Symptoms include "draft image specs for these docs", "we need images for X, write the prompts", "add visuals to my place-guide / blog / site", "image briefs for the Astro pages", "spec out the hero images", "write nano-banana prompts for the [N] guides", "we'll need more image specs in the future", "create visual briefs", "image-spec the chapter openers". Produces (1) a master SPEC document inheriting palette + register + avoid list from a brand doc, (2) per-source-file visuals docs with N image entries each, (3) an INDEX.md status tracker, (4) all prompts ready to paste into the generator. Portable across repos and brand systems; the brand identity is a parameter, not hard-coded. NOT for one-off single-image generation in chat (just write the prompt directly). NOT for listing photography (that's human-photographer territory governed by brand DESIGN.md §7). NOT for logo / icon / vector design.
---

# image-spec

A reusable workflow for producing nano-banana-ready (or any-modern-text-to-image-ready) per-image specification files that attach to existing markdown documentation. The skill captures the discipline learned from authoring 32 image specs across a 10-file place-guide system: one master spec inherits the brand identity; per-file specs hold the actual prompts; an INDEX tracker shows generation status.

The skill assumes you already have a brand identity (palette, register, avoid list) and a set of source docs that need images. It does not invent visual identity from scratch.

## When to use

Trigger when you have all three:

1. A **set of markdown documents** that need images embedded.
2. A **brand identity document** (or equivalent: design tokens, palette, photography register rules, an "avoid list" of cliches). For Wu and Kin this is `docs/brand/DESIGN.md`. For other repos: whatever defines the look.
3. A clear **image budget** in mind (per-file count and roles: hero / section divider / detail).

Skip when:

- You're generating a single one-off image in chat (just write the prompt directly).
- You have no brand identity yet (define it first; this skill is downstream).
- The images are listing photography (a real photographer goes; DESIGN.md §7 governs).
- The artifacts are vector design (logos, icons, line illustrations rendered as SVG). Different workflow.

## Inputs the skill needs from the operator

Ask for these at the start. If any are missing, ask before drafting.

| Input | Example | Required |
|---|---|---|
| **Source docs** | List of markdown files (or glob like `docs/blog/*.md`) | yes |
| **Brand doc** | `docs/brand/DESIGN.md` (or equivalent path) | yes |
| **Output folder** | `docs/blog/_visuals/` or sibling pattern | yes |
| **Image budget** | "5 hero + 3 divider for full posts; 1 hero for short posts" | yes |
| **Spec system** | "`docs/specs/SPEC-NNN-<topic>-visuals.md`" or repo's convention | yes (or default to repo-local) |
| **Subject hints** | "this post talks about X, image should hint at Y" | optional but useful |
| **Target generator** | "nano-banana (default)", or "Imagen 3", "Midjourney v6", etc. | default to nano-banana |
| **Storage path for final PNGs/JPEGs** | `site/photos/blog/<slug>/<filename>` | yes |

## The 5-phase workflow

### Phase 1: Read the brand doc

Open the brand doc the operator pointed at. Extract:

- **Palette hex codes.** Note 4-8 tokens that will be cited inline in prompts.
- **Photography register rules.** What the brand says about lighting, lens, composition, post.
- **Aspect ratio conventions.** Hero / card / vertical-lifestyle standards.
- **Avoid list.** What the brand says NOT to do. This goes into every prompt's `avoid:` clause.
- **One-warm-accent rule** or equivalent. Most editorial brands have one.

If the brand doc does not say one of these, ask the operator before defaulting.

### Phase 2: Write the master visual spec

A single SPEC document at the repo's spec convention path (or `docs/specs/SPEC-NNN-<topic>-visuals.md` if the repo uses a numbered spec system; or a sibling `VISUALS-SPEC.md` next to the source docs if not).

Use **Template A** (below). The master spec defines:

- Audience and scope (which source docs)
- Visual identity inheritance (palette tokens cited inline, register rules quoted)
- Aspect ratio + pixel standard
- Filename convention
- Storage paths
- Per-image spec template (Template C, copied inline so each per-file spec is self-anchored)
- Cross-file consistency rules (what NOT to show across the set, continuity requirements)
- Generator-specific guidance (nano-banana paragraph prose discipline, etc.)
- Verification checklist

### Phase 3: Write the per-file visuals docs

One markdown file per source doc, all in the output folder. Use **Template B**. Each file:

- Names its source doc in frontmatter
- States its image count
- Lists each image entry using Template C
- Total images across all files matches the operator's budget

### Phase 4: Write the INDEX.md tracker

A single `INDEX.md` in the output folder. Use **Template D**. Columns:

```
# | Source | Role | Subject | Filename | Aspect | Status
```

Sort by source then by image number. Include a "generation order recommendation" block at the bottom (highest-impact first).

### Phase 5: Verify

Run the verification checklist (below) before declaring done. If anything fails, fix and re-run.

---

## Template A: master visual spec (SPEC document)

```markdown
---
spec_id: NNN
title: <Project> visual specification
status: active
authors: <name>
created: YYYY-MM-DD
last_updated: YYYY-MM-DD
domain: <project-domain>
related: [SPEC-XXX]  # optional, e.g., the content spec this visual spec supports
note: |
  Master visual specification governing per-file image specs in
  `<output-folder>/`. Inherits visual identity from `<brand-doc-path>`.
  Image-generation prompts target <generator>. Total budget: <N> images
  across <M> source docs.
---

# <Project> visual specification

The master visual spec governing every image generated for `<source-glob>`. Per-image briefs live in `<output-folder>/<source-slug>-visuals.md`; each brief follows the template in §7 below and inherits the constraints in §2-§6.

## 1. Audience and scope

**Audience.** Operator + image-generation passes (<generator>, future <next-generator>). Not end-user-facing.

**Scope.** <N> source docs:

- `<doc1.md>`, `<doc2.md>`, ...

**Budget:** <total> images total.

| File | Image count | Notes |
|---|---|---|
| `<doc1.md>` | <N> | hero + dividers |
| ... | ... | ... |

## 2. Visual identity inheritance

Authoritative source: [`<brand-doc-path>`](<relative-path>). Quoted inline below for execution-time reference.

### 2.1 Palette tokens

| Token | Hex | Role in images |
|---|---|---|
| `<token-1>` | `#XXXXXX` | <use> |
| ... | ... | ... |

### 2.2 Photography register

| Do | Don't |
|---|---|
| <do-1> | <dont-1> |
| ... | ... |

### 2.3 Cliche avoid list

Every prompt includes a negation clause covering:

- <item-1>
- <item-2>
- ...

## 3. Aspect ratio and pixel standard

| Role | Aspect | Retina target | Web-served | File-size cap |
|---|---|---|---|---|
| Hero | 16:9 | 2400 × 1350 | 1920 × 1080 | 200 KB JPEG q85 |
| Section divider | 3:1 | 1800 × 600 | 1440 × 480 | 120 KB |
| Detail still | 4:5 portrait | 1600 × 2000 | 1080 × 1350 | 180 KB |

## 4. Filename convention

```
<source-slug>-<role>-<subject-slug>.png
```

Roles: `hero`, `divider`, `detail`. Examples: `<doc-slug>-hero-<subject>.png`.

## 5. Storage paths

| Stage | Path |
|---|---|
| Generated working files | `_inbox/visuals-YYYY-MM/` |
| Approved masters | `<final-path>/<source-slug>/<filename>.png` |
| Web JPEGs | same dir, `<filename>.jpg` |

## 6. Cross-file consistency rules

1. <rule-1>
2. <rule-2>
3. (See §6 in this template's worked example for the place-guide system.)

## 7. Per-image spec template

(Inline copy of Template C.)

## 8. Generator-specific guidance

(Inline copy of the "<generator>-specific guidance" section, below.)

## 9. Sample full entry

(Inline copy of the worked example, below.)

## 10. Generation and review workflow

1. **Draft.** Per-file specs in `<output-folder>/` carry `Status: drafted`.
2. **Generate v1.** Operator pastes the prose prompt into <generator>. PNG to `_inbox/visuals-YYYY-MM/`.
3. **Iterate.** Change one structured knob, regenerate. Track in `## Iteration log` appended to the spec entry.
4. **Approve.** Move PNG to `<final-path>/`. Update status to `approved`.
5. **Compress for web.** JPEG q85.
6. **Embed in source.** Add `![alt](<relative-image-path>)` at the position specified.
7. **Bump source's `> Updated YYYY-MM-DD.`** at the top.

## 11. Verification

(See "Verification checklist" in this skill.)
```

---

## Template B: per-file visuals doc

```markdown
---
source_guide: <relative-path-to-source.md>
images: <N>
spec: <relative-path-to-master-spec.md>
last_updated: YYYY-MM-DD
---

# Visuals: `<source.md>`

<N> images: <role-summary, e.g., "hero + 2 dividers">. <One-line note on any per-source consistency rules, e.g., "Pine-tree species must match Image X in Y-visuals.md per master-spec §6 continuity rule.">

---

(<N> Template C entries, each separated by `---`.)
```

---

## Template C: per-image entry (the heart of the skill)

```markdown
### Image N / <role>: <short title>

**Position in source:** `<source.md>` → ## <section-name> (placement note)
**Aspect:** <ratio>, <pixel target>
**Filename:** `<source-slug>-<role>-<subject-slug>.png`
**Status:** drafted | generated v1 | approved

**Prompt (paste into <generator>):**

> <Natural-language paragraph 2-5 sentences. Order: subject, composition,
> camera + lens, lighting, palette anchors with hex codes, register reference,
> mood, texture, in-flow negations, aspect at the end.>

**Structured knobs (for iteration):**

- **subject:** <one line>
- **composition:** <foreground / midground / background, rule of thirds, leading lines>
- **camera + angle:** <eye-level | low | high | drone; framing: wide | medium | close>
- **lens / depth of field:** <focal length (24mm wide, 35mm normal, 50mm portrait, 85mm telephoto, 105mm macro); shallow / medium / deep DoF>
- **lighting:** <time of day, direction, quality: ambient | hard | soft>
- **palette anchors:** <2-4 hex tokens from brand doc, one warm accent>
- **register:** editorial photography, [reference: Cereal | Apartamento | Kinfolk | MONOCLE | other]
- **texture:** <film stock feel: 35mm grain, medium format clarity, digital crisp>
- **mood:** <one word + one adjective>
- **avoid:** <comma-separated cliché list: brand-wide avoids + image-specific avoids>
- **aspect:** <16:9 | 3:1 | 4:5 | 4:3>
```

---

## Template D: INDEX.md tracker

```markdown
---
purpose: tracker for the <N> <project> images
audience: operator (image-generation pass)
spec: <relative-path-to-master-spec.md>
last_updated: YYYY-MM-DD
---

# <Project> visuals: image tracker

<N> images total across <M> source docs. Status values: `drafted` → `generated v1` → `approved`.

## All images

| # | Source | Role | Subject | Filename | Aspect | Status |
|---|---|---|---|---|---|---|
| 1 | <source.md> | hero | <subject> | `<filename>.png` | 16:9 | drafted |
| 2 | <source.md> | divider | <subject> | `<filename>.png` | 3:1 | drafted |
| ... | ... | ... | ... | ... | ... | ... |

## Status legend

- **drafted**: spec written, not yet generated. The starting state.
- **generated v1**: first generation done, PNG in `_inbox/visuals-YYYY-MM/`.
- **approved**: moved to `<final-path>/`, JPEG exported, embedded in source.

## Generation order recommendation

Start with the highest-impact images that anchor your most-active or most-visible source docs.

1. **`<filename>.png`** (Image N): <why first>
2. **`<filename>.png`** (Image M): <why second>
3. ...

## Cross-file consistency check

Before approving any image, confirm against the master spec's cross-file rules:

- [ ] <rule-1>
- [ ] <rule-2>
- ...
```

---

## Discipline rules (apply to every entry)

### Em-dash discipline

**Never use em-dashes (`—`, U+2014).** This is a project-wide formatting rule for Han. Replace with:

- `:` for definition-style breaks
- `,` for parenthetical asides
- `(` `)` for nested clauses
- `.` for sentence breaks
- `-` for compound modifiers
- `–` (en-dash) for ranges

Sweep the output with `grep -n "—"` before declaring done.

### Single warm accent rule

Every image has exactly one ochre / amber / bronze / warm point. If you find yourself describing two warm accents in one prompt, you have used one too many. The brand restraint is what gives the palette personality.

### No identifiable faces

Privacy + brand-voice avoidance of stock-people register. Hands, feet, distant silhouettes are OK. Faces never. Same rule for any private building exteriors the brand wants to keep off-camera (e.g., a tenant's apartment block).

### Hex codes inline

Cite 2-4 specific hex codes from the brand doc inside the prose paragraph. `#FAFAF7` reliably anchors color in nano-banana more than "pale stone-white." Use the brand's token names AND the hex.

### Camera + lens + film stock named

Anchor the photography register with specific gear words. "Shot on a Leica Q at 24mm, ISO 400, subtle 35mm film grain" beats "professional editorial photography." Pick one camera-lens combo per image; common useful ones:

- Wide environmental: Leica Q at 24mm, Sony A7 IV at 24mm
- Standard editorial: Fujifilm X-T5 at 35mm, Leica M11 at 35mm
- Portrait register (no face, just subject isolation): Sony A7 IV at 50mm
- Detail / macro: Nikon Z7 II with 105mm macro

### Editorial-magazine reference library

Pick one magazine reference per image. Each is a register trigger that nano-banana respects:

| Reference | Register |
|---|---|
| **Cereal** | Calm, restrained, architectural, neutral palettes |
| **Apartamento** | Lived-in, warm, slight clutter, real-people interiors |
| **Kinfolk** | Soft, neutral, lifestyle, "slow living" |
| **MONOCLE** | Urban, design-forward, daylight, internationalist |
| **The Gentlewoman** | Editorial portrait register (no faces; treat as still-life) |
| **Apollo** | Art-and-design adjacent, museum register |
| **The New York Times Magazine** | Documentary, photojournalistic edge |

### In-flow negations

Nano-banana does not take separate negative prompts; put them in the prose. "No people, no swan boats, no neon, no áo dài" inside the paragraph works.

### Aspect ratio at the end

Last clause of the prose: "Aspect 16:9." More reliable than placing it first.

### Diacritics in alt text, ASCII in filenames

Filename: `dalat-hero-xuan-huong-fog.png`. Alt text in the source-doc embed: "Xuân Hương Lake at pre-dawn fog, Da Lat."

---

## Generator-specific guidance

### Nano-banana (Gemini 2.5 Flash Image): default

What works:

- Natural-language paragraphs over tag-style prompts
- Hex codes inline (respects them more than color names alone)
- Magazine references as style triggers
- In-flow negations
- Aspect ratio at the end of the prose

What does not:

- Separate negative-prompt fields (it doesn't have one)
- Tag-soup keyword stacking ("ultra realistic, 8k, masterpiece, trending on artstation"): stripped, doesn't help
- Text overlays / on-image text: unreliable; expect re-renders
- Identifiable real-person faces: should be avoided for privacy AND because generation is uneven

### Imagen 3 / Imagen 4

Comparable to nano-banana. Same prose discipline works. Imagen sometimes interprets composition cues (rule of thirds, leading lines) more literally. Test before committing the master spec to Imagen-specific phrasing.

### Midjourney v6 / v7

Different prompt grammar. Tag-style and parameter flags (`--ar 16:9 --style raw --stylize 250`) work better than pure prose. The skill's prose paragraph can be converted by prefixing with the style-cue parameters; the per-image knobs map cleanly:

- `--ar` from `aspect`
- `--style raw` for the editorial register
- `--stylize` low (50-150) for documentary, high (500+) for stylized

### Stable Diffusion / Flux

Tag-style. The "structured knobs" in Template C convert well to a tag list. Negative prompts go to the negative field, not the main prompt.

If switching generators, write a one-page conversion appendix at the bottom of the master spec. Don't rewrite every per-image entry.

---

## Worked example (gold standard)

The reference implementation. The first prompt produced by every new use of this skill should read like this.

---

### Image 1 / Hero: Xuân Hương Lake pre-dawn fog

**Position in source:** `dalat.md` → ## Orientation (top of file, image precedes the first paragraph)
**Aspect:** 16:9, 2400 × 1350
**Filename:** `dalat-hero-xuan-huong-fog.png`
**Status:** drafted (unverified, not yet generated)

**Prompt (paste into nano-banana):**

> A still, pre-dawn photograph of Xuân Hương Lake in Da Lat, seen from the eastern boardwalk looking west. Low mist rises in slow curls off the water; the opposite hillside of pines emerges from the fog as soft silhouettes. A single Art Deco lamppost stands in the foreground left, its glass warm with the only point of color. Shot on a Leica Q at 24mm, ISO 400, blue-hour ambient light, no direct sun, subtle 35mm film grain. Editorial photography in the register of Cereal magazine. Palette: cool stone-whites (#FAFAF7) for the mist, muted teal-greens (#1F4D3F) for the pines, a single warm ochre (#C9A878) on the lamp glass. No people, no swan boats, no wedding photo crews, no neon, no oversaturation. Quiet, contemplative atmosphere. Aspect 16:9.

**Structured knobs:**

- **subject:** Xuân Hương Lake, eastern boardwalk vantage, pre-dawn fog
- **composition:** lamppost foreground left, lake midground, pine hill background; rule of thirds, leading line along the boardwalk edge
- **camera + angle:** eye-level, slightly raised, looking west
- **lens / depth of field:** 24mm wide; lamppost sharp, hills soft, medium DoF
- **lighting:** blue-hour ambient, no direct sun, low contrast
- **palette anchors:** stone-50 (#FAFAF7), teal-700 (#1F4D3F), single ochre-400 (#C9A878)
- **register:** editorial photography, Cereal magazine reference
- **texture:** subtle 35mm film grain, slight imperfection
- **mood:** quiet, contemplative
- **avoid:** swan boats, wedding crews, neon, AI sheen, áo dài, conical hats, dramatic skies, oversaturation
- **aspect:** 16:9

---

### Image 2 / Divider: District 10 alley at golden hour

**Position in source:** `hcmc.md` → ## Orientation (top of file, image precedes the first paragraph)
**Aspect:** 16:9, 2400 × 1350
**Filename:** `hcmc-hero-d10-alley-golden.png`
**Status:** drafted

**Prompt (paste into nano-banana):**

> A horizontal photograph of a quiet residential alley in District 10, Hồ Chí Minh City, late afternoon golden hour. Narrow alley about 3 metres wide, two- and three-storey townhouses on both sides in faded pastels: stone-yellow, soft ochre, weathered cream stucco. Several scooters parked along the right side, helmets hooked on rear racks. Laundry hangs from a single upper-floor balcony on the left, catching the warm light. A small purple bougainvillea spills from a low wall mid-frame. The alley pavement is patched concrete, recently wet. Late-afternoon sun rakes across the upper third of the right wall, warm and oblique. Shot on a Leica Q at 24mm, ISO 400, slight 35mm film grain, available light only. Editorial register in the style of MONOCLE travel photography. Palette: ochre-50 (#F5EDDA) and ochre-900 (#4A1B0C) in the wall stucco range, stone-200 (#E0DCD3) pavement, teal-700 (#1F4D3F) bougainvillea foliage, single ochre-400 (#C9A878) on the sunlit wall highlight. No people, no faces, no riders on scooters, no high-rise visible. Residential, lived-in, post-3pm-storm calm. Aspect 16:9.

**Structured knobs:**

- **subject:** D10 residential alley, late afternoon, parked scooters, hanging laundry, bougainvillea
- **composition:** Alley vanishing point center-distance, scooters right, balcony with laundry upper-left, bougainvillea mid-frame
- **camera + angle:** Eye-level, mid-alley, looking down its length
- **lens / depth of field:** 24mm wide, medium DoF, scooters and walls sharp, far end soft
- **lighting:** Late-afternoon golden hour, sun raking across upper-right walls
- **palette anchors:** ochre-50 (#F5EDDA) and ochre-900 (#4A1B0C) walls, stone-200 (#E0DCD3) pavement, teal-700 (#1F4D3F) bougainvillea, ochre-400 (#C9A878) wall highlight
- **register:** Editorial travel, MONOCLE reference
- **texture:** stucco crack-detail, patched concrete, slight film grain, recent rain sheen
- **mood:** Lived-in, residential, post-storm calm
- **avoid:** Bùi Viện neon, Notre Dame, Bến Thành market crowd, áo dài, conical hats, motorbike traffic in motion, AI sheen, "Vietnam alley cliché" with hanging plants overcrowding
- **aspect:** 16:9

---

These two examples come from the place-guide visual system; they demonstrate the discipline at full quality.

## Cross-file consistency: classic rules

Every multi-image set has its own continuity story. Common rules to consider:

1. **Subject continuity.** If two images show the same kind of thing (a pine tree, a specific architectural style, a recurring object), they should look like the same thing across frames.
2. **Privacy / brand-protection.** Some buildings, locations, or signage should not appear in the set (occupied tenant property, branded competitor venues, anything the brand wants to keep off-camera).
3. **No identifiable human faces** (default).
4. **Single non-photographic frame, or all photographic.** Mixing illustration into a photo set is rare; the place-guide system has exactly one map illustration and treats everything else as editorial photography.
5. **At least one "everyday reality" frame per location.** Not all hero landmarks. Some weather, some neighborhood, some lived-in moment.
6. **Single warm accent per image.** Two warm points violates the brand restraint.

Each new use should write its own version of this list in §6 of the master spec, based on the brand and the set.

## Verification checklist

Run before declaring done. Each item must pass.

- [ ] **File presence.** Master spec exists; each per-file spec exists; INDEX.md exists.
- [ ] **Image count.** `grep -c '^### Image' <output-folder>/*.md` totals match the operator's budget.
- [ ] **Master-spec self-containment.** A fresh reader opens the master spec alone and can write a generator prompt for any image using only the template + brand-doc citations. No third file needed.
- [ ] **Palette coherence.** Spot-check 3 random prompts: each names palette anchors from brand-doc hex tokens; each has at least one editorial-magazine register reference; each has an `avoid:` clause matching brand-doc rules.
- [ ] **Privacy + brand rules.** No prompt names an identifiable face. No prompt shows a brand-protected exterior. No prompt uses brand-avoided cliches.
- [ ] **Em-dash discipline.** `grep -n "—" <output-folder>/*.md <master-spec-path>` returns empty.
- [ ] **Cross-file consistency.** Continuity rules from master-spec §6 hold across the set.
- [ ] **Filename convention.** Every filename matches `<source-slug>-<role>-<subject-slug>.png`. No spaces, no diacritics in filenames.
- [ ] **Alt text** in any future source-doc embeds uses diacritics; filenames stay ASCII.
- [ ] **Source-doc impact.** Master spec is referenced from each affected source doc's frontmatter or footer (optional but recommended).

## Anti-patterns to avoid

These behaviors degrade the output. Watch for them in your own drafts.

1. **Tag-soup prompts.** "Ultra realistic, 8k, masterpiece, professional photography, award winning." Strip it. Magazine reference + camera/lens/film stock + lighting + palette anchors is the working register.
2. **Vague palette ("warm tones," "blue sky").** Brand-doc hex anchors are the rule.
3. **Cliche subjects sneaking in.** If you wrote "áo dài" without noticing, you did. Re-read the brand avoid list before each prompt.
4. **Two warm accents in one image.** The bronze rule. Once you write two, remove one.
5. **Forgetting aspect at the end.** Nano-banana cares about order. Put it last.
6. **Em-dashes.** Hyphens and en-dashes are fine. Em-dashes are not.
7. **Specific real names without permission.** "Dr. Rafi Kot at Family Medical Practice" in a prompt names a real doctor. If naming, get permission or genericize to "a Vietnamese GP clinic."
8. **Generating before approving the spec.** Run the verification before sending to nano-banana, not after.
9. **One-shot generation expectations.** Plan for 2-3 iterations per image, changing one knob at a time.

## Skill output: minimum

When invoked, this skill produces:

1. One master spec markdown file at the repo's spec convention path.
2. One per-source-doc visuals markdown in the output folder.
3. One `INDEX.md` tracker in the output folder.
4. A short summary message: which files were created, total image count, what the operator should do next (pick top of generation-order list, paste prose into nano-banana).

Optional follow-ons (ask the operator):

- Embed `![alt](path)` references in the source docs at the specified positions (only after first generation, not at spec time).
- Update the repo INDEX.md / README.md with pointers to the new spec.
- Add a `visuals:` line to source-doc frontmatter pointing at the per-file spec.

## Cheat sheet (one-screen reminder)

```
PROMPT ORDER (last clause = aspect):
  subject → composition → camera + lens →
  lighting → palette (hex inline) → magazine register →
  mood → texture → in-flow negations → aspect

KNOBS:
  subject / composition / camera+angle / lens / lighting /
  palette / register / texture / mood / avoid / aspect

RULES:
  no em-dashes
  one warm accent per image
  no identifiable faces
  hex codes inline (not just color names)
  camera + lens + film stock named
  magazine reference (Cereal/Apartamento/Kinfolk/MONOCLE/...)
  in-flow negations
  aspect at the end of prose

OUTPUTS:
  master spec  (SPEC-NNN-<topic>-visuals.md)
  per-file specs (<source-slug>-visuals.md, one per source)
  INDEX.md tracker

WORKFLOW:
  drafted → generated v1 → approved
```

## Where this skill came from

Distilled from authoring 32 image specs for the Wu and Kin place-guide system (`tieubao/properties` repo, `docs/place-guides/_visuals/`, governed by `docs/specs/SPEC-003-place-guide-visuals.md`). That set covers Da Lat, HCMC, Da Nang, Hoi An, Kon Tum, plus the Vietnam suite (primer + 4 deep dives). Use it as the worked-example body if you need a real-world template to point at.
