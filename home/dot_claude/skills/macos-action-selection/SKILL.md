---
name: macos-action-selection
description: Use BEFORE saying "needs you to click X" / "I'm stalled waiting" / "(a) you bring X up / (b) fallback" on macOS. Picks the right rung of the L0-L4 action ladder: L0=plain CLI (`open -a Tailscale`, `defaults write`, `gh`, `op`), L1=`osascript`/JXA for Apple-scriptable apps, L2=`shortcuts run <name>` for user-defined Shortcuts, L3=`mcp__macos-use__*` for any UI with an Accessibility tree (sub-second, narrow grant), L4=`mcp__peekaboo__*` for canvas/Chromium/AX-opaque UIs. Symptoms include "click the menubar item", "enable Tailscale/Bluetooth/Wi-Fi", "toggle System Settings", "fill the form in this desktop app", "Claude is waiting for you to click", any AFK GUI block on a Mac. Always check L0 first (CLI-first principle); vision-loop is L4 last resort.
---

# macOS action selection

When you're about to declare "needs you to click X" on macOS, walk this ladder top-down first. Most "GUI-only" actions have a CLI / AppleScript / Shortcut path that's faster and doesn't need a human round-trip.

## Quick decision

| Situation | Tool |
|---|---|
| "Open / launch / bring up / start X" | `open -a "<App Name>"` |
| Apple-scriptable app (Finder, Music, Safari, Mail, Notes, Reminders, Calendar, System Events, Chrome) | `osascript -e 'tell application "X" to ...'` |
| User has a Shortcut defined for the flow | `shortcuts run "<name>"` |
| Click a menubar item / toggle a Settings switch / native AppKit/SwiftUI control | `mcp__macos-use__*` (L3) |
| Canvas-rendered UI (Figma internals, Blender, games, Excalidraw) | `mcp__peekaboo__*` (L4) |
| Chromium-rendered internals (Slack/Discord/Notion native apps, Electron) | `mcp__peekaboo__*` (L4) |
| Anything that has a CLI or API | **Use the CLI / API, not a GUI driver.** |

## The ladder

```
L0  Plain CLI / open -a / defaults / gh / op / app-specific CLIs
L1  osascript / JXA
L2  shortcuts run "<name>"
L3  mcp__macos-use__*   (AX tree, no vision, sub-second)
L4  mcp__peekaboo__*    (screenshot + click/type + AX, vision when AX fails)

↑ cheaper, faster, narrower permission grant
↓ broader coverage, slower, brittle
```

**Stop at the first rung that works.** Don't jump straight to L4 just because it's the most general.

## Canonical example: Tailscale

If Tailscale on the machine is off and you need a tailnet host reachable:

- ❌ "Tailscale FQDN didn't resolve. (a) Bring Tailscale up — needs you. (b) Use mDNS fallback."
- ✓ `open -a Tailscale` then verify `tailscale status` after a 2-3s pause. Auto-connects if the user has previously authed.

Reaching L0 first solves it; L4 was overkill. This is the failure mode the ladder is designed to prevent.

## Reach-order debugging

When you think you've hit a GUI block, check in this order before declaring it:

1. **Is there a CLI?** Try `which <app>`, `man <app>`, `<app> --help`. Many apps ship a CLI helper (`tailscale`, `gh`, `op`, `mas`, `defaults`).
2. **Can you just launch it?** `open -a "<App Name>"` is often the whole answer for "enable X" / "start X" tasks; menubar apps usually auto-connect on launch when previously authed.
3. **Apple-scriptable?** `osascript -e 'tell application "<X>" to get version'` returning a value means the app has a scripting dictionary and you can drive it through `osascript`. Most of Apple's own apps do.
4. **Shortcut defined?** `shortcuts list | grep -i <kw>` to see if the user has a Shortcut for this.
5. **AX-tree visible?** L3 via `mcp__macos-use__*`. Most native AppKit/SwiftUI apps + System Settings expose AX.
6. **AX-opaque?** L4 via `mcp__peekaboo__*` as last resort.

## Tool details

### L3: macos-use MCP

- Source: [`mediar-ai/mcp-server-macos-use`](https://github.com/mediar-ai/mcp-server-macos-use). Swift; build from source.
- Built binary lives at `<checkout>/.build/release/mcp-server-macos-use`.
- TCC: grant Accessibility to the built binary. Screen Recording NOT needed.
- Strength: fast (sub-second), structured (AX labels), narrow grant.
- Weakness: no AX tree → no help (Chromium internals, canvas, games).

### L4: Peekaboo MCP

- Source: [`openclaw/Peekaboo`](https://github.com/openclaw/Peekaboo) (steipete). `brew install steipete/tap/peekaboo`.
- Binary at `/opt/homebrew/bin/peekaboo` (Homebrew symlink); MCP via `peekaboo mcp`.
- TCC: grant Screen Recording + Accessibility + Event Synthesizing.
- Strength: covers canvas / Chromium / AX-opaque UIs.
- Weakness: slower (vision loop), broader permission grant.

## Install (per machine, one-time)

### macos-use

```bash
# Clone wherever you keep experiments
git clone --depth=1 https://github.com/mediar-ai/mcp-server-macos-use.git
cd mcp-server-macos-use
```

**Build will fail on Swift 6.3+ as-is.** Upstream dep `modelcontextprotocol/swift-sdk@0.11.0` ships a `Task { @MainActor in ... }` pattern in `Sources/MCP/Base/Transports/NetworkTransport.swift` that triggers `[#SendingRisksDataRace]` under strict-concurrency Swift 6. The file is `NWConnection`-transport code; stdio MCP doesn't touch it. Fix:

```bash
# Resolve once so .build/checkouts/swift-sdk exists
swift package resolve

# Edit .build/checkouts/swift-sdk/Package.swift, add to the MCP target:
#     exclude: ["Base/Transports/NetworkTransport.swift"],
# (place between `dependencies: [...],` and `swiftSettings: [...]`)

# Now build
swift build -c release
```

Register with Claude Code:

```bash
claude mcp add macos-use -- "$(pwd)/.build/release/mcp-server-macos-use"
```

Then grant Accessibility to the binary via System Settings → Privacy & Security → Accessibility (drag binary in, toggle on).

**Maintenance caveats:**
- The `.build/checkouts/swift-sdk/Package.swift` patch is regenerated on `swift package resolve / update / reset`. Re-apply after any of those.
- Rebuilding the binary changes its signature; macOS may invalidate the Accessibility grant. Re-grant if AX errors appear post-rebuild.
- Long-term fix: fork swift-sdk and pin to the fork in `mcp-server-macos-use/Package.swift`, OR wait for an upstream Swift-6-compat release.

### Peekaboo

```bash
brew install steipete/tap/peekaboo
claude mcp add peekaboo -- /opt/homebrew/bin/peekaboo mcp
peekaboo permissions  # check what's already granted; grant remaining via System Settings
```

## Reversibility rule (still binding)

The ladder lets you **act on reversible** GUI actions without waiting. Your global tool-selection reversibility gate still binds:

- **Act:** `open -a`, toggling Bluetooth, switching Wi-Fi, opening a file, clicking a Connect button on an authed app.
- **Ask:** sending money via payment SaaS, force-pushing to main, deleting data, anything irreversible or with shared-state side effects.

Walking the ladder is not cover for skipping the irreversible-action ask.

## Anti-patterns

| About to do | Stop |
|---|---|
| Declare "needs you to click X" before trying L0-L2 | Walk the ladder first. |
| Use `mcp__peekaboo__*` when AX would work | L3 first. Faster, narrower TCC grant. |
| Use `mcp__macos-use__*` when `open -a` works | L0 first. CLI-first principle. |
| Run `swift package update` on the macos-use checkout | Don't, without re-applying the NetworkTransport exclude patch. |
| Use the ladder to bypass the reversibility gate | The gate is independent. |

## Related

- Tool-selection rule: `~/.claude/CLAUDE.md` "Tool selection" section
- Browser-specific picks: `browser-tool-selection` skill
- Cloudflare-specific picks: `cloudflare-tool-selection` skill
