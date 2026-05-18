---
name: bot-reply-formatting
description: Use when designing or maintaining a Telegram/Discord bot reply or Hermes skill output. Picks the right format per platform — Discord rich embeds with fields/colors/thumbnails first, Telegram bold + inline-code + line breaks first, code blocks ONLY when columns must align across rows. Provides Discord embed anatomy, severity color palette, calibration recipe for code-block cell budgets, and the column-layout / bar-fill / duration-compaction tricks for the code-block fallback. Symptoms include "format for the bot", "show this in Telegram", "Discord embed with fields", "make this fit on phone", "build a status reply", "this wraps on my phone", "the alert looks like a JSON dump", "use channel mentions", "bot reply layout".
version: 0.3.0
---

# bot-reply-formatting

Bot-reply layout for Telegram and Discord. **Default to platform-native rich UI; code blocks are the fallback for genuinely tabular data.** Renamed from `chat-codeblock-tables` (v0.2.0) after evidence that my own outputs over-reached for code blocks even when embeds would have read better — the previous name baked in the wrong priority.

## Provenance / what's verified

| Claim | Status (2026-05-06) |
|---|---|
| Telegram code block at 35 cells wraps on Han's current iPhone | **verified** (live screenshot) |
| Telegram code block at 28 cells fits without wrap on Han's current iPhone | **inferred-not-verified** |
| Discord code block in narrow pane fits ~30 chars + per-row emoji aligned (Mochi watchlist) | **verified** (Mochi screenshot) |
| Discord native embeds read better than code-block dumps for non-tabular data (alerts, multi-section reports, narratives) | **verified** (Hermes-bad vs Dwarves-onboarding screenshots) |
| Discord embed limits: 256 title, 4096 description, 25 fields × (256 name / 1024 value), 2048 footer, 6000 total, 10 embeds/message | **verified** (docs.discord.com 2026-05-06) |
| Discord field `inline: true` lays out 3-up on desktop, stacks on mobile | **community-reported** |
| `▓` / `░` render with identical cell width on iOS/Android | **inherited** from opencode-usage |
| Discord Android single-backtick inline code can drop to non-monospace | **community-reported** |

## 1. Pick the format first (priority order inverted from v0.2)

| Priority | Format | Use when |
|---|---|---|
| 1 | **Discord rich embed** (Discord-only) — title, description, fields, color bar, thumbnail, footer, channel/user/emoji mentions | Status reports, alerts, multi-section roundups, narratives, anything with hierarchy or category. Default for any Discord bot reply that's >2 short lines. |
| 2 | **Plain prose with markdown** — bold labels, inline-code values, line breaks, channel/user/emoji mentions | Single-fact replies, conversational messages, Telegram messages where embeds aren't available. |
| 3 | **Code-block table** — fixed-cell-width monospace inside `<pre>` / triple-backtick fence | ONLY when columns must align across rows (progress bars, ranked lists with right-aligned numerics, tabular numerical data). See §5. |
| 4 | **Code-block JSON / log dump** | Truly raw debug data the user needs to copy. Almost always the wrong choice for an alert — extract the actionable fields into prose or embed-fields instead. |

**The big anti-pattern**: dumping multi-section data into one giant code block. Each section deserves its own embed field on Discord, or its own bold-prefixed paragraph on Telegram. Only the truly tabular sub-section (right-aligned numerics) earns a code block.

## 2. Discord rich embed anatomy

```
[author icon] [author name]                       ← author block (small grey, top-line)
[colored left bar — embed.color]
[bold big title with optional emoji]              ← embed.title (256 chars, markdown OK)
[description paragraph with **markdown**, channel  ← embed.description (4096 chars, markdown OK)
 mentions like #arrival, custom emoji, links]

[Field 1 name]      [Field 2 name]      [Field 3]  ← inline:true → 3-up grid on desktop, stack on mobile
[Field 1 value]     [Field 2 value]     [Field 3]    (each field: name 256 chars, value 1024, markdown OK)

[Full-width Field name]                            ← inline:false → full-width (default)
[Full-width Field value with linebreaks
 and code blocks if needed]

[thumbnail.url]                                    ← top-right small image
[image.url]                                        ← bottom large image
[footer icon] [footer text]   [timestamp]          ← footer (2048 chars)
```

Hard limits per embed: 6000 chars total across title + description + field-names + field-values + footer + author. Up to 10 embeds per message. Fields max 25.

### 2a. Mapping Hermes use cases to anatomy

**Status report (e.g. opencode-usage on Discord)**:
- `color`: severity from §3
- `title`: `📊 opencode-go usage`
- Fields, all `inline: true`:
  - "Rolling" / "0% · 4h45m"
  - "Weekly" / "9% · 4d17h"
  - "Monthly" / "5% · 23d11h"
- `footer`: `🟢 healthy · 💰 balance $0`

No code block needed at all on Discord — three inline fields render the same data with proper hierarchy.

**Daemon-down alert (vps-mon `daemon-down-substrate`)**:
- `color`: 🔴 critical (`0xED4245`)
- `title`: `[mac-mini-danang] daemon-down-substrate`
- Fields:
  - `inline:true` "Host" / `mac-mini-danang`
  - `inline:true` "Severity" / `CRIT`
  - `inline:false` "Down units" / `• foundation.d.hermes-agent`
  - `inline:false` "Pinned but missing" / `• foundation.d.hermes-agent` `• foundation.d.openclaw-gateway` `• foundation.d.openclaw-caddy`
  - `inline:false` "Remediation" / triple-backtick code block with the literal `ssh ... bootstrap ...` command
- `footer`: `vps-mon · <timestamp>`

The current default dumps a JSON blob into a "Detail" field — that's wrong. Pull each actionable item into its own field; reserve code blocks for the literal command the user copies.

**Multi-section roundup (foundation-d-upgrade-check)**:
- One embed, multiple fields — OR — multiple embeds in one message.
- Each section gets its own field with `inline:false`:
  - "🛠️ Top Tools" / [code block ONLY for the right-aligned numerics — Tool, Calls, %]
  - "☁️ Top Skills" / [code block ONLY for Skill, Loads, Edits, Last used]
  - "📈 Activity Patterns" / [no code block — bullet list "Mon: 0, Tue: 6, Wed: 6..."]
- Don't cram all three into one mega `<pre>` block.

**Narrative / onboarding (Dwarves Discord welcome screen)**:
- `image`: cover banner
- `title` and `description`: bold section headings + emoji bullets + channel mentions
- Fields per CTA section ("Gain full access", "Share and Earn", "Hang Around")
- Zero code blocks.

### 2b. Native primitives — prefer over text labels

| Want to write | Wrong (plaintext) | Right (Discord native) |
|---|---|---|
| Reference a channel | `the #arrival channel` | `<#CHANNEL_ID>` → renders as `#arrival` clickable |
| Mention a user | `ping @nikki` | `<@USER_ID>` |
| Mention a role | `the @ops role` | `<@&ROLE_ID>` |
| Custom server emoji | `:dwarves_check:` | `<:dwarves_check:EMOJI_ID>` |
| Animated custom emoji | n/a in plain text | `<a:name:EMOJI_ID>` |
| Hyperlink | bare URL | `[link text](https://...)` (works in title, description, field values, footer) |
| Heading inside description | bold workaround | `# Heading` markdown (Discord supports H1-H3 in description/field-value as of 2024) |

Custom emoji and channel/user mentions only render where the bot has access to those IDs. For cross-server skills, fall back to Unicode emoji + plaintext `#channel`.

## 3. Severity color palette (Discord embeds)

Use these as `embed.color` integers so all Hermes alerts share a consistent visual grammar:

| State | Emoji | Hex | Decimal | Use for |
|---|---|---|---|---|
| healthy / ok | 🟢 | `#57F287` | `5763719` | All-clear status reports |
| info / neutral | 🔵 | `#5865F2` | `5793266` | Informational, no action needed |
| burning / warn | 🟡 | `#FEE75C` | `16705372` | Trending hot but still under threshold |
| high / urgent | 🟠 | `#ED9F1B` | `15572763` | Action required soon |
| critical / fail | 🔴 | `#ED4245` | `15548997` | Daemon down, payment failed |
| muted | ⚫ | `#4F545C` | `5198428` | Disabled / paused / silenced |

Pick the worst-row severity for the embed color (same threshold rule as the footer emoji in §6).

## 4. Telegram counterpart (no embeds)

Telegram has no rich embed primitive. Closest equivalents:

| Discord primitive | Telegram equivalent |
|---|---|
| Embed title | `*bold title*` (MarkdownV2) or `<b>bold</b>` (HTML) on its own line |
| Embed description | Plain paragraph with markdown |
| Field name | `*Field name*` on its own line |
| Field value | Next line, plain or `inline-code` |
| Inline (3-up) layout | **No equivalent** — must stack vertically |
| Color bar | **No equivalent** — convey severity with status emoji + text |
| Footer | Italic line at bottom: `_vps-mon · 16:50_` |
| Channel mention | `@channel_username` (renders as link if public) |
| User mention | `@username` or `<a href="tg://user?id=...">name</a>` (HTML) |
| Custom emoji | Telegram Premium custom emoji (`<emoji id="123">🤖</emoji>` HTML) — assume not available |
| Hyperlink | `[text](url)` MarkdownV2, `<a href="url">text</a>` HTML |
| Heading | Bold + line break (no real heading primitive) |

For multi-section status, structure as bold-headed paragraphs separated by blank lines. Reserve code blocks for the same column-alignment edge case as Discord.

## 5. Code-block fallback (only when columns must align)

When you've fallen through to a code block, the rules from v0.2.0 still apply.

### 5a. Cell budget — calibrate

Send this to your bot's saved-messages / DM chat from the actual target device:

````
test
```
24..|....|....|....|....|....|.... 36
28..|....|....|....|....|....| 32
32..|....|....|....|.....| 32
40..|....|....|....|....|....|....|....|....| 40
```
````

Pick the largest row that doesn't wrap; round down to a multiple of 4 for headroom.

### 5b. Empirical anchors

| Device / context | Width | Source |
|---|---|---|
| Han's current iPhone, Telegram DM portrait | ≥28, <35 | This session |
| iPhone SE 1st gen, Telegram DM portrait | ~35 | opencode-usage v0.1 |
| Discord narrow desktop pane (Mochi watchlist) | ~30 + emoji | This session |
| Telegram community SOP "mobile-friendly" | ≤40 | Telegram dev forum |
| Desktop | 60+ | Don't optimize |

### 5c. Heuristic when calibration not possible

- Telegram, mobile-target unknown → **32**
- Discord, mobile-target unknown → **32–36**
- Cross-platform, must work on smallest device → **28**

### 5d. Column widths — derive from data

For each column, find the widest possible value, add 1 cell of breathing room, right-align numbers, left-align text. The 5-column "label / bar / gap / pct / gap / reset" pattern from opencode-usage is one example, not the canonical structure. Mochi watchlist uses ticker / price / pct / emoji — different columns, same principle.

### 5e. Bar fill (only for progress bars)

```python
filled = 0 if pct == 0 else max(1, round(pct * N / 100))  # N = bar width
empty  = N - filled
bar    = "▓" * filled + "░" * empty
```

- `▓` (U+2593) + `░` (U+2591). Both Block Elements; equal-width claim is inherited, not personally re-tested.
- The `max(1, ...)` floor on nonzero pct is load-bearing.
- `▰▱` / `■□` / `🟩⬜` are claimed-broken. Swap glyphs first if alignment looks off.

### 5f. Duration compaction

`4h 45m` → `4h45m`, `4d 17h` → `4d17h`, truncate to 2 units (`4d17h` not `4d17h45m`).

### 5g. Per-row emoji

- **Discord**: works in code blocks (Mochi watchlist verified).
- **Telegram**: claimed-misaligning inside `<pre>` — calibrate before trusting.

## 6. Aggregate footer pattern

For status reports, one aggregate emoji + word in the footer keyed off the worst row's severity:

| max(pct) across rows | Status |
|---|---|
| 0–49% | 🟢 healthy |
| 50–79% | 🟡 burning |
| 80–94% | 🟠 high |
| 95–100% | 🔴 critical |

On Discord, the same severity drives `embed.color`. On Telegram, the footer is the only signal.

## 7. Anti-patterns

- ❌ **Reaching for a code block by reflex.** Most Hermes alerts read better as Discord embed fields. Code blocks are the fallback for tabular numerics, not the default.
- ❌ **Dumping multi-section data into one `<pre>` block.** Each section deserves its own field (Discord) or bold-prefixed paragraph (Telegram).
- ❌ **JSON blobs in alerts.** Extract the 2-4 actionable fields (Host, Severity, Down units, Remediation command) into named fields. Raw JSON is for debug logs.
- ❌ **Markdown tables (`| col |`)** — neither platform renders them.
- ❌ **Plaintext channel/user references on Discord** — use `<#id>`, `<@id>`, `<:emoji:id>`.
- ❌ **Hard-coded "magic" cell budgets.**
- ❌ **Bar fills without min-1 floor.**
- ❌ **Three-unit durations** (`4d17h45m`).
- ❌ **Designing for desktop first.**
- ❌ **Generalizing platform rules without re-testing** on the target device.

## 8. Verification recipe before shipping

1. Picked the right format? (Embed > prose > code-block.)
2. If embed: under 6000 chars total, ≤25 fields, severity color set?
3. If code-block: cells counted; widest expected value tested; sent to target device's saved-messages chat and visually inspected?
4. Native primitives used where applicable (channel/user/emoji mentions on Discord)?
5. If using non-`▓░` glyphs, alignment tested at 0%, 1%, 5%?
6. Per-row emoji on Telegram code-block? Calibrate first.

## 9. Cross-link from a consumer skill

```markdown
## Style

Follows `bot-reply-formatting` (in `~/.claude/skills/`). Format chosen: [Discord embed | Telegram prose | code-block table]. [Then describe the skill-specific fields, color, calibrated cell budget, etc.]
```

## 10. References

- [Discord embed object docs](https://docs.discord.com/developers/resources/message) — title 256 / description 4096 / fields 25 × (256/1024) / footer 2048 / 6000 total / 10 embeds per message.
- [Telegram Bot API styled text](https://core.telegram.org/api/entities) — pre, code, bold, italic entity types.
- [Telegram community ~40-char SOP](https://community.latenode.com/t/how-to-create-fixed-width-text-formatting-in-telegram-bot-messages-using-php/22297).
- [Discord mobile codeblock monospace gotchas](https://support.discord.com/hc/en-us/community/posts/4407328946839-Mobile-code-blocks-lacking-monospace-font).
- Empirical sources: `tools/hermes/agent/skills/opencode-usage/SKILL.md`, Mochi Bot watchlist + request screenshots, Hermes `foundation-d-upgrade-check` and `vps-mon daemon-down-substrate` screenshots (2026-05-06 — examples of code-block over-reach), Dwarves Discord welcome (2026-05-06 — embed done right).
