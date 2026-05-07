# Dotfiles sync log

Append-only record of Claude-assisted sync sessions. Each entry logs
what changed and when. Read by Claude at the start of each sync for
context.

---

## [2026-05-08] S-55 ship: batch mode for secret-cache-read @ Hans Air M4

Profiled `fish --profile-startup -lic exit` on Hans-Air-M4 to find
top-self-time contributors. Secret pipeline was ~70 ms (4 × ~17 ms
per `$_sc` call), 40% of 177 ms total warm startup.

Replaced 4-fork pattern with single `secret-cache-read --batch` call:
N pairs in argv, NUL-separated output, fish-side `string split0` + loop
to apply `set -gx`. S-54 ordering enforced inside the script
(`OP_SERVICE_ACCOUNT_TOKEN` resolved first, `export`ed for pass 2 so
later `op read` fallbacks have bearer auth in env).

Measured savings on Hans-Air-M4 (warm cold-fish, 5 runs each):
  - Before: ~170 ms
  - After:  ~155 ms
  - Δ: ~15 ms (-9%)

Smaller win than predicted (~50 ms). Reason: each `security
find-generic-password` call has irreducible kernel overhead (~13 ms);
batching only collapses bash-startup overhead (~3 ms × 4 = ~12 ms).
Honest delta documented in spec trade-offs.

Spec: docs/specs/S-55-batch-secret-cache-read.md (status: done).
Verification:
  - chezmoi execute-template renders correctly with batch invocation
  - fish -n on rendered output: clean
  - shellcheck on secret-cache-read: clean
  - smoke test (string length only, never echoed): all 4 vars populated
  - 5× cold-fish-startup timing: 0.15-0.16 s steady state

Branched off `main` (PR #76 still open with S-51 scope). Will need a
trivial 3-way merge with PR #76 (the gate change `is-interactive →
is-login`) and PR #77 (S-54 explicit-first-load, now superseded by the
internal two-pass in this script).

Marginal improvement. Worth shipping. Not headlined.

---

## [2026-05-07] sync @ Hans Air M4

Apply pending PRs landed: chezmoi apply absorbed PR #72 (SSH privacy gate
in /dotfiles-sync) and PR #69 (Brewfile cask "zen" canonical rename).

SSH config.d (privacy gate, all on-disk fragments now `.local` + 1P-backed):
  - rename trading-egress-tokyo → trading-egress-tokyo.local
    (1P backup pre-existed: "SSH config: trading-egress-tokyo" in vault Trading)
  - create 1P Secure Note "SSH config: egress" in vault Trading
    for the existing egress.local fragment (Tailscale alias to
    trading-egress-tokyo). egress.local already correctly named.
  - mini.local was already conformant (1P/Private).

Brewfile (core - home/dot_Brewfile.tmpl):
  - removed brew (8 stale, not installed on this Air): ffmpeg, go, librsvg,
    node, protobuf, ripgrep, sqlite, terraform
  - removed cask: codex
  - added brew: bats-core, mosh, pandoc, rust, wireguard-tools

Brewfile (local - ~/.Brewfile.local):
  - added cask: antigravity, calibre, chrysalis, codexbar, conductor, cursor,
    grandperspective, hyprnote, opencode-desktop, tana, tor-browser, zen
  - added brew: doctl, duti, gitup, lume, markdown-oxide, ocaml, rclone,
    subversion, tldx, xcodegen, hashicorp/tap/terraform
  - kept (per user choice, despite supersedes by zoxide / fish): z, zsh

VS Code extensions:
  - added (5): docker.docker, dwarvesf.md-ar-ext, github.copilot-chat,
    ms-vsliveshare.vsliveshare, ocamllabs.ocaml-platform
  - removed (1): openai.chatgpt (uninstalled)

Claude skills (suppressed via ~/.config/dotfiles/skills.local, all local):
  - agentkernel, bot-reply-formatting, cashflow-append, cashflow-correct,
    cashflow-report

Untracked drift left for user (not actioned):
  - legacy brew migrations (recommend uninstall): hub, pipx, the_silver_searcher,
    yarn (+ python@3.10 tag-along of pipx)
  - cosmetic: microsoft-auto-update (Office), swiftdefaultappsprefpane (one-off),
    zen-browser (alias artifact for cask "zen")
  - fisher.fish (we use chezmoiexternal, not fisher) - skip recommended

---

## [2026-05-06] sync @ Hans Air M4

Config:
  - statusline: switch hostname source from `hostname -s` (returns generic "Mac")
    to `scutil --get LocalHostName` (returns "Hans-Air-M4"), matching the
    SessionStart machine-banner hook. User noticed the statusline read `@Mac`
    instead of the actual machine name; root cause was the macOS default
    smb-style hostname clobbering the more useful LocalHostName.

Other drift deferred (Brewfile, .chezmoiscripts/*, dotfiles-sync.md command
edits) — needs its own dedicated sync pass.

---

## [2026-05-05] security: rewrite history to scrub leaked SSH file @ Hans Air M4

Following the privacy-gate work in PR #72, decided to also retroactively scrub
the leaked `home/dot_ssh/config.d/private_mini.local` blob from git history
on `main`. Earlier "leak is theatre, just sanitize forward" framing was
revised: tooling was clean (no open PRs to rebase, no signed commits, no
tags in range, both forks 33 days behind the leak), so the work-to-payoff
ratio for a full rewrite was actually defensible.

Sequence:
  1. Verified backups: 1P Secure Notes `op://Private/SSH config: mini` and
     `op://Trading/SSH config: trading-egress-tokyo` both readable; on-disk
     `~/.ssh/config.d/mini.local` and `~/.ssh/config.d/trading-egress-tokyo`
     both intact.
  2. Tagged `pre-rewrite-2026-05-05` on origin (backup ref before rewrite).
  3. `git filter-repo --invert-paths --path home/dot_ssh/config.d/private_mini.local --force`
     rewrote 95 commits in 0.07s. The leaked blob
     `9763977e34868e6c5145ae13f87547c096d37276` is now orphaned locally.
  4. Branch-protection ruleset `"Protect main"` (id 14664913) was disabled
     for ~13 seconds via gh API (PUT enforcement=disabled), force-pushed
     `main` (`164eaeb` -> `7d2ff43`), then re-enabled (PUT enforcement=active).
  5. Deleted the `pre-rewrite-2026-05-05` tag on origin (kept locally) so
     no ref pins the orphaned commits.

Verification: `gh api .../contents/home/dot_ssh/config.d/private_mini.local?ref=7d2ff43`
returns 404. Direct blob SHA lookup still resolves on GitHub (orphan persists
until GitHub's internal GC, typically days-weeks). For hostname-grade leaked
content, accepting that residual SHA-cache rather than escalating to GitHub
Support.

Forks/collaborators: 2 forks (hieu-ht, redstrike) at SHA `f8c3c48` are 42
commits behind the leak window and never pulled it. 3 admin collaborators
(monotykamary, lmquang, zlatanpham) had no recent activity within the
21-minute leak window. No coordination message sent.

Local backup tag `pre-rewrite-2026-05-05` (pointing to `164eaeb`, the
pre-rewrite tip) retained on Hans Air M4 for ~24h then will be deleted.

---

## [2026-05-05] feat(/dotfiles-sync): privacy gate for SSH fragments + 1P-backup check @ Hans Air M4

Follow-up to the SSH fragment refactor: the `/dotfiles-sync` command was the
upstream cause of the leak (PR #69). Detection step surfaced new SSH fragments
as a 3-way classify (core/local/skip) with no privacy gate, so `mini.local`
got routed to `core` and committed plaintext into a public repo.

Updates to both mirror copies of `dotfiles-sync.md`:

- **Detection**: each new SSH fragment is now tagged `[clean]` or `[private]`
  based on a heuristic (Tailscale `.ts.net` FQDN, IP in HostName, multi-segment
  internal hostnames, non-standard SSH port, purpose-revealing identity-file
  names like `id_ed25519_trading_vps`).
- **Classification**: SSH fragments are now FOUR-way (core / local / private /
  skip). The `private` route renames to `*.local` (gitignored) and creates a
  1P Secure Note titled `SSH config: <name>`. Repo is PUBLIC; flagged-private
  fragments must NEVER go to core.
- **Backup-status check (notify-only)**: scan `~/.ssh/config.d/*.local`
  fragments without a matching 1P Secure Note. Parallels the existing SSH-key
  audit. Drops `OP_SERVICE_ACCOUNT_TOKEN` per S-49 dual-mode so the lookup
  sees the user's full vault list (Notes may live in Private or Trading), not
  just the SA-scoped subset.
- **Action table**: new row "Back up SSH fragment privately" with the literal
  `op item create` command. Existing "Track SSH configs" row now reads
  "Track SSH configs (core)" and adds "only after verifying NO infra
  fingerprint" as a guard.
- **Report template**: SSH fragments show `[clean]` or `[⚠ private]` flags;
  added a "SSH fragment backup status" section parallel to "SSH backup
  status".

Heuristic smoke-tested locally on three synthetic fragments (clean / private
hostname / private port): all classified correctly. Mirror parity preserved
(`/usr/bin/diff` returns 0).

---

## [2026-05-05] security: move private SSH host fragments out of public source @ Hans Air M4

PR #69 landed `home/dot_ssh/config.d/private_mini.local` as plaintext into
the public dwarvesf/dotfiles repo (commit `a1f532f`). Source exposed:
internal Tailscale hostname `mac-mini-danang`, mDNS hostname
`Mac-mini.local`, SSH user `server`, identity file path. The `private_`
prefix only sets mode 0600 on the deployed file; the source on GitHub was
world-readable.

**Pattern decision:** machine-local file (`~/.ssh/config.d/*.local`,
gitignored) + 1Password Secure Note backup, restored via a one-line
`op read` on fresh-machine bootstrap. Rejected `onepasswordRead` (would
trigger biometric on every `chezmoi apply`, violates design philosophy
#5 "apply must be silent and idempotent"). Rejected `encrypted_` (chezmoi
age) because the source still leaks file existence/structure and adds
key-management surface for non-secret-grade hostname data. The local-only
pattern aligns with existing `*.local` conventions (Brewfile, fish, tmux,
gitconfig) and `dot_ssh/config.tmpl` already does `Include config.d/*` so
untracked drop-ins work for free.

**Bundled `trading-egress-tokyo`** (deferred Option A from PR #69 sync log)
under the same pattern: contained a public VPS IP, non-standard SSH port,
and purpose-revealing key name. Now lives only at
`~/.ssh/config.d/trading-egress-tokyo` on Hans Air M4 with backup at
`op://Trading/SSH config: trading-egress-tokyo/notesPlain`.

**Git history:** NOT rewritten. Repo is public, has 2 forks, 6 stars; the
plaintext blob is in commit `a1f532f` and was likely fetched by watchers
within the merge window. Force-push is theatre with coordination cost.
Treating the leaked hostname `mac-mini-danang` as already public going
forward; Tailscale ACL + SSH key remain the actual security boundary, not
hostname obscurity.

Changes:
  - `git rm home/dot_ssh/config.d/private_mini.local`
  - `chezmoi forget ~/.ssh/config.d/mini.local` (deployed file preserved)
  - `.gitignore`: dropped the `!home/dot_ssh/config.d/*.local` negation
    that was added in PR #69; SSH fragments named `*.local` are now
    blocked from `git add` defense-in-depth-style.
  - `docs/guide.md`: added "Walkthrough: restore private SSH host
    fragments" + a warning callout in "add an SSH host" about what
    not to commit.

1Password Secure Notes created (Hans Air M4 session):
  - `op://Private/SSH config: mini/notesPlain`
  - `op://Trading/SSH config: trading-egress-tokyo/notesPlain`

Verification: `chezmoi apply --dry-run` shows no drift; `ssh -G mini`
still resolves to `mac-mini-danang` (the deployed `~/.ssh/config.d/mini.local`
remains in place); `git ls-files home/dot_ssh/config.d/` empty.

---

## [2026-05-05] feat: track `vn-contract-format` Claude skill @ Hans Air M4

Adopted user-authored skill `~/.claude/skills/vn-contract-format/` into the
managed surface at `home/dot_claude/skills/vn-contract-format/`.

Skill contents (3 files):
  - `SKILL.md` (344 lines) -- print-ready Vietnamese legal documents
    workflow (biên bản thanh lý, giấy uỷ quyền, etc.) with markdown +
    python-docx generator, A4 / TNR 13pt styling.
  - `references/build_bien_ban_thanh_ly.py` (453 lines)
  - `references/build_giay_uy_quyen.py` (293 lines)

Verified `chezmoi managed | grep vn-contract` lists all 4 entries; dry-run
shows zero drift (source = target on this host). Will deploy on Mac mini
on next `chezmoi apply`.

---

## [2026-05-03] sync: Brewfile + SSH + gitconfig batch @ Hans Air M4

Multi-batch sync session. Brewfile + SSH + gitconfig changes; some asks
turned out to be no-ops because the state was already correct.

### Batch 2 (this session continuation): SSH + gitconfig

SSH:
  - tracked `~/.ssh/config.d/mini.local` -> `home/dot_ssh/config.d/private_mini.local`
    (Tailscale + LAN-fallback hosts for `mini`. Internal hostnames only,
    safe for public repo.)
  - **`~/.ssh/config.d/trading-egress-tokyo` -> Option A (local-only, deferred decision):**
    contains a public IP, non-standard SSH port, and purpose-revealing
    key name. dwarvesf/dotfiles is PUBLIC. User chose to keep it on
    Hans Air M4 only for now, will revisit (likely Option B: 1P-templated
    when they want it on Mac mini too). No chezmoi adopt, no gitignore
    change needed -- file simply remains untracked on disk. Future
    `/dotfiles-sync` runs will continue to surface it; that's the
    intended re-prompt cadence.

gitconfig:
  - absorbed local `[init] templatedir = ~/.git_template` into
    `home/dot_gitconfig.tmpl`. Post-edit `chezmoi cat ~/.gitconfig` matches
    disk byte-for-byte.

Casks ("absorb to core: 1password, font-jetbrains-mono, nordvpn, raycast"):
  - All 4 were already in core (Brewfile). No source edits needed.
  - 1Password.app, Raycast.app, NordVPN.app verified PRESENT in /Applications
    (installed via direct download, not brew). Brewfile entries serve as
    fresh-machine bootstrap; on this machine they're already covered.
  - font-jetbrains-mono is the only genuine miss. User installs manually.

Zed settings ("keep my local version"):
  - `chezmoi status` reported `MM` but `diff <(chezmoi cat) ~/.config/zed/settings.json`
    returned exit 0. No actual content drift. The `MM` is a cosmetic stale-cache
    in chezmoi state DB, not real divergence. Leaving alone.

Gitignore:
  - added negation `!home/dot_ssh/config.d/*.local` so SSH fragments with
    mDNS-style names (e.g. `mini.local`) can be tracked without removing
    the broader `*.local` machine-override pattern.

Side find: confirmed the fish-shadows-`diff` footgun still bites. Used
`/usr/bin/diff` throughout this batch.

### Batch 3 (continuation): zen rename + zed state-cache refresh

Brewfile:
  - renamed `cask "zen-browser"` -> `cask "zen"` per upstream brew alias
    (Zen Browser cask was renamed; both names worked but `zen` is now
    canonical. Verified via `brew info --cask zen-browser` resolving to
    `zen`.)

Zed settings.json:
  - User asked to "override dotfiles by my local version", but verified
    the rendered template and disk are byte-identical (md5
    206831e8b5b55e2ac9cb985fb324b3be on both sides). The `MM` flag in
    `chezmoi status` was metadata-cache lag, not actual content drift.
    Resolved with `chezmoi apply --force ~/.config/zed/settings.json`
    (safe given the md5 match): file unchanged, MM cleared.
  - No source edit needed; the template is correct.

User-requested install/absorb to core (9 items):
  - All 9 already in core Brewfile. No source edits needed for them.
  - Already installed locally (no action): node, ripgrep, pnpm, zoxide.
  - Need install (user runs manually after permission hook): rustup,
    font-jetbrains-mono-nerd-font.
  - **Risky** (already in /Applications via direct install): 1password,
    raycast, nordvpn. `brew install --cask` would need `--force` to
    overwrite. For 1Password specifically this could orphan vault data
    and signed-in account state. Halted; awaiting user decision.

### Batch 1 (earlier this session): 6 packages to core Brewfile

Brewfile (core, AI Tools section):
  - added brew: opencode (was npm-only; now via brew)
  - added brew: ollama (local LLM runner)
  - added brew: playwright-cli (standalone Playwright runner)

Brewfile (core, macOS Apps section):
  - added cask: tailscale-app (renamed from "tailscale" upstream)

Already in Brewfile, reaffirmed as core (still missing on this machine,
user installs manually after brew CLI permission):
  - brew: agent-browser
  - brew: tmux

Stale-comment cleanup:
  - dropped "opencode via: npm i -g opencode-ai" (now via brew)
  - dropped opencode-ai from npm-globals comment

Skipped this round (deferred to next sync):
  - 22 other untracked brew packages (incl. pandoc, rclone, xcodegen)
  - 14 other untracked casks (incl. cursor, zen, tor-browser, conductor)
  - 56 stale brew + 8 stale cask entries (no removals this run)
  - VS Code extension drift (5 new, 1 stale)
  - SSH config absorption (mini.local, trading-egress-tokyo)
  - zed/settings.json `MM` drift (needs merge decision)
  - .gitconfig drift (likely template re-render)
  - 1 SSH key without 1P backup

Pre-existing Brewfile bug surfaced (NOT introduced this run): `brew "terraform"`
fails on `brew bundle install` because terraform was removed from the main
Homebrew tap (BSL license). Fix: change to `brew "hashicorp/tap/terraform"`.
Filed mentally as next-sync follow-up.

Claude skill drift detection: clean (0 entries surfaced) - successful first
post-S-50 sync, the new check works as designed.

---

## [2026-05-03] feat(S-50): `/dotfiles-sync` detects user-authored Claude skill drift @ Hans Air M4

Background: commit `0ce60e8` (#63, 2026-04-30) wired `~/.claude/skills/`
into the chezmoi-managed surface but adoption was opt-in per skill.
Today's audit found 8 of 9 user-authored skills unversioned and at risk
of loss on a fresh-machine bootstrap.

One-shot absorption (all 8 promoted as **core** -- generic personal
workflows, no machine-specific paths -- verified by grepping for owner
identifiers; only hit was a doc example showing what NOT to write):

- browser-tool-selection
- cashflow-close
- cloudflare-tool-selection
- extract-workflow
- incident-workflow
- ingest-to-wiki
- playwright-record
- reconcile-properties

Ongoing detection added to `/dotfiles-sync`: new section in Step 2 scans
`~/.claude/skills/` for entries neither in `chezmoi managed` nor in
`~/.config/dotfiles/skills.local`. Step 4 prompts core/local/skip; Step 5
maps the choices to `chezmoi add` or an append to the local-mark file.
Plugin-installed skills (`ouroboros:*`, `superpowers:*`, etc.) live under
`~/.claude/plugins/` and are naturally filtered out.

Verification: 8 spec tests passed (absorption sanity, idempotence, clean
detection, positive detection of fake skill, suppression via
`skills.local`, cleanup, plugin filter, project/user copy parity).

Mirrored both copies of the slash command (`.claude/commands/dotfiles-sync.md`
and `home/dot_claude/commands/dotfiles-sync.md`); diff exits 0.

**Follow-up same-day:** ran `chezmoi apply ~/.claude/commands/dotfiles-sync.md`
to deploy the new section live on this machine (post-apply diff exit 0).
Updated user-facing docs: bumped `docs/guide.md` "10 dimensions" to 11,
added a "Claude skills" row to README.md's drift table, added a row to
guide.md's local-files and quick-change tables, and authored a full
"Walkthrough: back up a Claude skill" section. `verify-dotfiles` subagent
ran 6 checks (shellcheck, fish syntax, chezmoi dry-run, managed-count,
mirror parity, skill-drift detection): 6/6 passed. Side find: fish's
`diff` function shadows `/usr/bin/diff`; future scripts should use
`command diff` or absolute path - not blocking S-50 but a footgun worth
recording.

---

## [2026-05-01] docs: dedicated `docs/1password.md` workflow doc @ Hans-Air-M4

After the S-47 → S-49 redesign arc shipped, the inline service-account
sections in `CLAUDE.md` and `docs/guide.md` told the right story but
lacked a single-place explainer that ties together the mental model,
the dual-mode design, vault tiering (S-46), trade-offs, and the spec
chain. Added `docs/1password.md` as the source-of-truth narrative;
inline sections now point at it.

Also fixed two stale references found during audit:
- `README.md:185`: SA-token paragraph implied the old auto-load model.
  Rewritten to reflect dual-mode and link to the new doc.
- `docs/specs/S-42` postscript: only mentioned S-47, breaking the
  supersession chain for readers landing on S-42. Now shows the full
  chain S-42 → S-47 → S-49 and points at `docs/1password.md`.

CLAUDE.md and `docs/guide.md` link to `docs/1password.md` from their
service-account sections so future Claude sessions discover the
narrative entry-point first.

No behavior changes; docs only.

---

## [2026-05-01] dotfiles-sync: drop SA token before SSH-audit check @ Hans-Air-M4

Follow-up to S-49 in `home/dot_claude/commands/dotfiles-sync.md` (and the
project mirror at `.claude/commands/dotfiles-sync.md`). The skill runs
inside Claude Code's Bash tool, which inherits `OP_SERVICE_ACCOUNT_TOKEN`
under the new dual-mode model. Two of its `op`-using checks needed
`env -u OP_SERVICE_ACCOUNT_TOKEN` so they see the user's full vault list
(SSH keys live in `Private`, not `Trading`):

- `op account get` precondition gate (line 71)
- `fish -l -c 'dotfiles ssh audit'` invocation (line 72)

Without the unset, the SSH-audit step would report "0 of N keys backed
up" because the SA-scoped view of 1P doesn't see Private items. Updated
the explanatory comment to reference S-49 (was S-42).

The Keychain-cache check (line 95) reads macOS Keychain, not 1P, so
needs no change.

---

## [2026-05-01] S-49: dual-mode `op` via fish interceptor @ Hans-Air-M4

S-47 had restored multi-vault biometric in the daily shell by removing
`OP_SERVICE_ACCOUNT_TOKEN` from auto-load — but at the cost of the original
S-42 capability: agent subprocesses (Claude Code's Bash tool runs zsh)
could no longer do ad-hoc `op read op://...` mid-session. User wanted both.

**Design.** Auto-load the token globally so subprocesses inherit bearer auth.
Intercept `op` inside interactive fish via a tiny function
(`home/dot_config/fish/functions/op.fish`) that runs
`env -u OP_SERVICE_ACCOUNT_TOKEN command op $argv` when
`status is-interactive`. Subprocesses don't see the fish function and call
the binary directly with the token in env. Net: daily shell biometric and
multi-vault, every subprocess (including Claude Code) headless and SA-scoped.
No per-launch wrapper required.

**Changes:**
- New: `home/dot_config/fish/functions/op.fish` (5-line interceptor)
- Re-added `OP_SERVICE_ACCOUNT_TOKEN` entry to `home/.chezmoidata/secrets.toml`
- Removed the S-47 guard from `dotfiles secret add` (auto-load is the
  intended path again)
- S-47 frontmatter set to `status: amended by S-49`
- `with-agent-token` retained as a debug escape hatch
- Auto-memory rewritten to describe dual-mode

**Verification (all from a fresh `fish -i -c` after `chezmoi apply`):**
- `OP_SERVICE_ACCOUNT_TOKEN` prefix `ops_` in env ✓
- Interactive `op vault list` returns 8 vaults ✓
- `bash -c 'op vault list'` returns 1 vault (Trading) ✓
- `with-agent-token op vault list` returns 1 vault (Trading) — escape hatch
  still works ✓
- `command op vault list` returns 1 vault (Trading) — bypasses interceptor ✓
- `fish -n` clean on all touched function files ✓

**Trade-off:** token is back in shell env (S-47's strict guarantee gone).
Same blast-radius profile as the original S-42 model. Accepted because the
interceptor neutralises the daily-shell side effect that drove S-47, and
the agent-capability win is significant.

---

## [2026-05-01] S-48: narrow `chezmoi apply` scope in `dotfiles secret` @ Hans-Air-M4

Surfaced during S-47 verification: a `--force` re-add of
`OP_SERVICE_ACCOUNT_TOKEN` ran a full-tree `chezmoi apply`, which rendered
the new entry into `~/.config/fish/conf.d/secrets.fish` and then aborted
on an unrelated Zed TTY-prompt failure. The script's revert path only
undid `secrets.toml`, not the deployed `secrets.fish`. Source/target
silently drifted; new fish shells continued loading the unwanted token.

**Fix:** scope `chezmoi apply` in `dotfiles secret add` and
`dotfiles secret rm` to the single target file
`~/.config/fish/conf.d/secrets.fish`. In `secret add`, the revert path
now also re-runs the narrow apply so target re-renders without the line
even when the original apply rendered it. `secret rm` benefits from the
narrowing alone (its revert is a no-op by design).

**Verification:**
- Pre-condition: pending Zed drift on `~/.config/zed/settings.json`
  (chaos input).
- Manually appended a test entry to `secrets.toml`, ran narrow
  `chezmoi apply ~/.config/fish/conf.d/secrets.fish`: exit 0,
  `secrets.fish` updated, Zed file untouched.
- Removed the test entry, re-ran narrow apply: `secrets.fish` cleaned,
  Zed file still untouched.
- `fish -n home/dot_config/fish/functions/dotfiles.fish` clean.

---

## [2026-05-01] S-47: opt-in `OP_SERVICE_ACCOUNT_TOKEN` via wrapper @ Hans-Air-M4

Daily `op` CLI was scoped to the `Trading` vault on this laptop because
`OP_SERVICE_ACCOUNT_TOKEN` was registered in `secrets.toml` (S-42 model)
and auto-exported by every fish login. Once the token is in env, `op`
switches to bearer auth and ignores the user's biometric session. The
user noticed: `op vault list` returned only `Trading`, all other vaults
invisible interactively.

**Fix:** unregistered the token from `home/.chezmoidata/secrets.toml`
and added a per-launch `with-agent-token` wrapper that injects the
token into the wrapped process only. Daily shells now do
`op whoami` → `USER_OF_ACCOUNT` (biometric), `op vault list` returns
all 8 vaults. Agent sessions that need ad-hoc `op read` opt in via
`with-agent-token claude`.

**Anti-regression:**
- `dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN` now refuses with a
  message pointing at the wrapper. `--force` overrides if genuinely
  needed.
- S-42 frontmatter set to `status: superseded by S-47` with an
  in-spec note. Spec body preserved as historical record.
- `CLAUDE.md` and `docs/guide.md` rewritten to centre on the wrapper
  and warn against re-registering the var.
- Auto-memory entry added for this Claude account so future sessions
  don't "helpfully" undo the change.

**Verification (all passed in `env -u OP_SERVICE_ACCOUNT_TOKEN fish -i`):**
- token absent from env after fresh fish login
- 8 vaults visible to bare `op vault list`
- `with-agent-token op whoami` returns `SERVICE_ACCOUNT`
- `with-agent-token op vault list` returns 1 vault (`Trading`)
- guard fires on `dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN`
- `--force` bypass works
- fish syntax clean on all touched functions

**Trade-off accepted:** default `claude` sessions lose ad-hoc `op read`
mid-session (S-42's stated capability). Sessions that need it prefix
the launch. The vast majority of secret access is via pre-registered
env vars resolved at shell startup (S-35), which `claude` still
inherits unchanged.

---

## [2026-04-28] claude overlay manages `permissions.defaultMode` @ Mac mini

Cross-machine drift surfaced after the morning catch-up sync: Mac Air's
Claude Code session shows the `>> bypass permissions on` badge, Mac
mini's does not. Root cause: Air had `permissions.defaultMode:
"bypassPermissions"` set locally (unmanaged by dotfiles), Mac mini had
no value.

**Fix:** added `permissions.defaultMode` to the personal overlay at
`home/dot_claude/modify_settings.json`. Uses the same `// fallback`
pattern as the other managed fields (only sets the value if absent),
and merges additively into `permissions` so guardrails-owned
`permissions.deny` survives. Updated CLAUDE.md scope description to
reflect that `permissions.defaultMode` is now ours, `permissions.deny`
remains theirs, and `hooks.PreToolUse` is an additive merge (the prior
"never touches PreToolUse" claim in the doc was inaccurate; fixed).

**Trade-off accepted:** every machine that syncs from this point boots
Claude Code in bypass-permissions mode by default. Per-tool confirmation
prompts disappear; hard-block hooks (pipe-to-shell, `rm -rf` of
`/`/`~`/`$HOME`) and guardrails' `permissions.deny` rules still fire.
Consistent with the existing `skipDangerousModePermissionPrompt: true`
default. Override locally by editing `~/.claude/settings.json` after
apply -- additive merge preserves any manually-set value.

**Verification:**
- shellcheck on `modify_settings.json` clean
- piped current settings through the script: `permissions.defaultMode`
  emitted as `"bypassPermissions"`, `permissions.deny` array intact
- `chezmoi apply ~/.claude/settings.json` succeeded silently
- `jq '.permissions.defaultMode' ~/.claude/settings.json` returns
  `"bypassPermissions"` post-apply

---

## [2026-04-28] catch-up sync + Zed panel-dock absorbed @ Mac mini

First sync on Mac mini after 17 upstream commits landed from Hans Air M4
(S-36 guardrails, S-42 service account, S-44/S-45 secret discipline,
S-46 multi-vault model, tunnel functions, Brewfile cleanup).

**Pre-apply blockers resolved:**
- `chezmoi init` re-run to pick up new template variables
  (`guardrails_variant` from S-36, `op_vault` from S-46). Without this,
  apply aborted on the new `run_onchange_after_claude-guardrails.sh.tmpl`.
- Local drift on `~/.config/zed/settings.json` absorbed into source. User
  had added `project_panel.dock=right`, `outline_panel.dock=right`,
  `collaboration_panel.dock=right`, `git_panel.dock=right`,
  `agent_servers.claude-acp.type=registry`, and `agent.dock=left`.
  These are sensible defaults; promoted to core so all machines pick
  them up.

**New packages on this machine (all classified skip):** 17 brew leaves +
3 casks were untracked, but every one is a non-issue:
- legacy from the Zsh/Prezto era (zsh, hub, the_silver_searcher,
  youtube-dl, z) - superseded by fish + gh + ripgrep + zoxide + yt-dlp
- transitive deps (shared-mime-info, hashicorp/tap/terraform - the latter
  is the tap form of `terraform` already in core)
- machine-specific tooling not worth promoting (gitup, llvm@21, rbenv,
  ruby, rust, subversion, typescript, yarn, pipx, htop)
- aliases of already-tracked packages (google-cloud-sdk = renamed
  gcloud-cli; zen-browser already added to core in the pulled
  commits; microsoft-auto-update is auto-installed by Office)

Nothing was added to `~/.Brewfile.local` this round - none of these are
worth tracking even per-machine. They stay installed but unmanaged.

**Stale entries deliberately kept:** `~/.Brewfile` lists 8 brews
(ffmpeg, go, librsvg, node, ripgrep, sqlite, terraform, tldr) and 2
casks (nordvpn, slack) that aren't installed on Mac mini. Not pruning
because they're real core packages used on Hans Air M4. Mac mini just
hasn't run `brew bundle` against the latest core list yet.

Repo changes:
  - home/dot_config/zed/settings.json.tmpl: absorbed 6 local keys
    (panel docks + agent_servers + agent.dock)

Skipped this sync (user choice):
  - `chezmoi apply` itself. Would deploy 14 upstream files and trigger
    `brew bundle` (which would install the 8 stale brews + 2 stale
    casks). User can run `chezmoi apply` separately when ready.
  - Pruning stale Brewfile entries.

---

## [2026-04-28] sync workflow hardening (re-verify gate) @ Hans Air M4

Sync session opened with a pasted prior-session report flagging two
blockers (chezmoi init required for `guardrails_variant` and `op_vault`;
Zed local drift on panel-dock keys). Re-verification on the live system
showed both already resolved: `~/.config/chezmoi/chezmoi.toml` carried
every required var, and `diff <(chezmoi cat ~/.config/zed/settings.json)
~/.config/zed/settings.json` was empty. The LLM (this session) had
parroted the stale claims as actionable blockers before checking,
which sent the user toward unnecessary interactive work.

Decisions:
  - 17 brew + 3 cask listed as new on this host: user said "skip all".
    Nothing added to `home/dot_Brewfile.tmpl` or `~/.Brewfile.local`.
  - 3 pulled upstream chezmoiscripts (`aa-init`, `ab-1password-check`,
    `zz-summary`) executed via `chezmoi apply` (run by user).

Workflow fix landed on `fix/sync-reverify-blockers` (a989bc7):
  - dotfiles-sync skill (both copies): new Step 2.5 forces re-derivation
    of every blocker claim from current state before reporting it.
    Step 3 report header now stamps timestamp, hostname, git rev so
    paste-ins from prior sessions are visibly snapshots.
  - CLAUDE.md: new "Pre-action verification" subsection at the top of
    `## Verification rules`, generalised beyond sync to any LLM-driven
    interactive prompt.

Branch not yet merged. Push + PR is a separate decision.

---

## [2026-04-23] docs cross-refs (S-42 in README, S-44 rule in CLAUDE.md) @ Hans Air M4

Post-ship audit caught two real documentation gaps:

1. `README.md` §Security covered the S-35 lazy-Keychain pattern but
   said nothing about the service account path (S-42) for agent
   subprocesses. A fresh reader would not discover this capability
   from the README alone.
2. `CLAUDE.md` carried the S-45 "never echo secret values" rule but
   not the S-44 standing rule ("shipping a spec = status + tasks.md +
   sync-log, all three, every time"). Future LLMs reading CLAUDE.md
   would miss it.

Both fixes are one-paragraph / one-bullet additions. No new spec (this
is a doc correction to reference existing specs, not a new design).

Repo changes:
  - README.md: new "Agents and non-interactive op read" paragraph in §Security
  - CLAUDE.md: new "Spec status discipline (S-44)" bullet in Important conventions

Non-fixes (deliberately skipped):
  - docs/guide.md: already has the full S-42 section; doctor check
    self-explanatory; S-45 is contributor-side, not user-side.
  - docs/llm-dotfiles.md: generic stack-agnostic pattern doc; 1P
    specifics do not belong.
  - SVGs: S-42 is a specialization of the S-35 flow; diagrams still
    accurate.

---

## [2026-04-23] S-45 stop echoing secrets in refresh @ Hans Air M4

Incident + fix in one entry.

**Incident (earlier same day):** during S-43 verification I simulated
the "empty Keychain" doctor branch by deleting an entry and then
re-cached it with `dotfiles secret refresh OP_SERVICE_ACCOUNT_TOKEN`.
The function printed `"Restart shell or: set -gx OP_SERVICE_ACCOUNT_TOKEN 'ops_...'"`
which echoed the raw service account token into the terminal (and
therefore into the Claude Code session transcript). User decided to
rotate the token in 1P; the rotation itself is out of scope of the
dotfiles repo.

**Root cause:** `home/dot_config/fish/functions/dotfiles.fish:257` in
the `dotfiles secret refresh` path had a success hint that interpolated
`$val` into its output. Any transcript-capturing environment
(screen recorder, LLM tool-call log, `script -a`, etc.) captured the
value.

**Fix (this PR, spec [S-45](specs/S-45-secret-refresh-no-echo.md)):**
Replaced the leaky hint with phrasing that references the variable
name only (`"Open a new shell ... to load the new value into $VAR"`).
Matches the already-safe wording in the `secret add` success path.

**Standing rule now in CLAUDE.md:** never echo resolved secret values.
Reference the var name or op:// ref instead. `secret-cache-read` is the
one exception (its stdout is captured by `()`, not printed).

**Audit result:** only one leak site existed. `dotfiles secret add/rm/list`
paths were checked and are clean. `secret-cache-read` is correct.
`chezmoi apply` path was cleaned up in S-35 and remains secret-free.

**Open follow-up** (not in this PR): `dotfiles secret add` passes the
value to `op item create` as a command-line argument, briefly visible
to local `ps`. Lower severity; documented in the spec as a known
limitation.

Repo changes:
  - docs/specs/S-45-secret-refresh-no-echo.md (new)
  - home/dot_config/fish/functions/dotfiles.fish: 2-line hint replacement
  - CLAUDE.md: new "Never echo resolved secret values" convention
  - docs/tasks.md: ticked S-45

---

## [2026-04-23] S-26 Brewfile cleanup @ Hans Air M4

Audit per spec [S-26](specs/S-26-brewfile-cleanup.md). Two changes
landed; everything else intentionally deferred.

Findings:
  - Real duplicate: `brew "tldr"` listed twice in the Core CLI block
    (the second had the descriptive comment). Fixed: kept the earlier
    occurrence, moved the comment onto it, deleted the duplicate.
  - False duplicate: `font-source-code-pro` and
    `font-sauce-code-pro-nerd-font` are separate fonts (original Adobe
    vs Nerd-Font patched). Added a one-line comment above the pair so
    future readers (including LLMs) do not dedupe them.

Verified but not acted on:
  - All casks resolve via `brew info --cask` (no renames needed).
  - No commented-out brew/cask entries exist; all `#` comments are
    install-path breadcrumbs for packages managed via cargo, npm, uv,
    or curl | bash. Keeping them.
  - `brew bundle check` exits 0 on the rendered `~/.Brewfile`.

Flagged for future decision:
  - `mise` + brew language runtimes (`go`, `node`, `python@3.12`,
    `elixir`, `rustup`) overlap. Not a typo, a design question. Left
    alone until the user picks a side.

Repo changes:
  - home/dot_Brewfile.tmpl: removed duplicate tldr, added font-pair comment
  - docs/specs/S-26-brewfile-cleanup.md: replaced stub with full audit
    spec, status=done
  - docs/tasks.md: ticked S-26

Standing rule from S-44 applied in this PR.

---

## [2026-04-23] S-44 spec status housekeeping @ Hans Air M4

Audit found 6 specs with stale status frontmatter despite having shipped:
S-32 (`planned`), S-36, S-37, S-38, S-39, S-41 (`proposed`). Root cause is procedural:
the SDD flow never required flipping status to `done` at ship time, so
frontmatter drifted from reality.

Two-part fix (spec [S-44](specs/S-44-spec-status-housekeeping.md)):
  - One-time: flip the five stale statuses, refresh tasks.md to list
    S-35 through S-44 in the appropriate section, document S-40 as
    intentionally unused (number gap, no spec).
  - Standing rule: from now on, shipping a spec includes flipping its
    status to done AND ticking its entry in tasks.md AND appending to
    the sync log. All three, not optional.

No runtime changes. No chezmoi apply needed. Pure bookkeeping.

Files changed:
  - docs/specs/S-44-spec-status-housekeeping.md (new)
  - docs/specs/S-{32,36,37,38,39,41}-*.md: status frontmatter only
  - docs/tasks.md: date + reconciliation for S-24 through S-44
  - docs/sync-log.md: this entry

---

## [2026-04-23] S-43 sync secret cache visibility @ Hans Air M4

Follow-up to S-42. The sync workflow did not surface registered-but-uncached
secrets, so a fresh machine that inherited the `OP_SERVICE_ACCOUNT_TOKEN`
registration but never triggered the first interactive biometric had no
feedback loop. Agents calling `op read op://...` would just fail silently.

Two additive, notify-only probes added (see spec
[S-43](specs/S-43-sync-secret-cache-visibility.md)):

  - `/dotfiles-sync` step 2: new "Secret cache status" block. Silent when
    all registered secrets are cached or when op is absent/unauthed.
    Gated on `op account list &>/dev/null` so headless machines stay quiet.
    Report category: "Secret cache (optional)" under step-3 format.
  - `dotfiles doctor`: new check after the SSH backup block. Iterates
    `secrets.toml`, probes Keychain per var. Reports `[ok]` when everything
    is cached, `[--]` (info) when any are empty, with a hint to run
    `exec fish` or wait for the next interactive shell.

Design choices recorded in the spec:
  - Info-level (`[--]`) not error (`[!!]`). Empty cache is a legitimate
    transient state on fresh machines.
  - Reachability of the 1P ref is NOT checked (would require live op call,
    would popup on miss). Presence of Keychain entry only.
  - Token identity is not special-cased. The probe is uniform across all
    registered vars; `OP_SERVICE_ACCOUNT_TOKEN` shows up like any other.

Verified both branches (all-cached, one-missing) on this machine.

Repo changes:
  - docs/specs/S-43-sync-secret-cache-visibility.md (new)
  - .claude/commands/dotfiles-sync.md: + "Secret cache status" scan block, + report line
  - home/dot_claude/commands/dotfiles-sync.md: identical mirror of project copy
  - home/dot_config/fish/functions/dotfiles.fish: + secrets.toml iterator in doctor

Not changed (intentionally):
  - secret-cache-read (probes are observational only)
  - secrets.fish.tmpl loop (no new registrations)
  - any .chezmoiscripts/ (apply path stays popup-free per S-35)

---

## [2026-04-23] S-42 service account agent auth @ Hans Air M4

New spec: [S-42](specs/S-42-service-account-agent-auth.md) -- document the
1Password service account pattern so Claude Code subprocesses can
`op read op://...` headlessly.

Root cause recap: `op` refuses to trigger biometric when stdin is not a TTY,
so agent subprocess reads fail silently. Service account bearer auth
bypasses biometric entirely once `OP_SERVICE_ACCOUNT_TOKEN` is in env.

Registered locally (this machine only, per-user action, not shared):
  - `dotfiles secret add OP_SERVICE_ACCOUNT_TOKEN "op://Private/op-service-account-trading/credential"`
  - Token scoped server-side to the `Trading` vault in 1Password
  - First fish login triggered one biometric; all subsequent shells silent

Repo changes (shared):
  - docs/specs/S-42-service-account-agent-auth.md (new)
  - CLAUDE.md: expanded "Secret injection" section from two backends to three patterns
  - docs/guide.md: added "Service account for agent subprocess `op read`" subsection under §6
  - home/.chezmoidata/secrets.toml: added `OP_SERVICE_ACCOUNT_TOKEN` registry entry (op:// ref only, not a value)

Not changed (intentional -- existing infra absorbs this):
  - secret-cache-read helper
  - secrets.fish.tmpl template loop
  - dotfiles secret subcommands

Blast radius note recorded in the spec: service account token reads every
vault scoped to it. Keychain entry is per-user encrypted at rest, same
threat model as `ANTHROPIC_API_KEY`. Recommended mitigation (dedicated
`Agents` vault) is documented but not enforced; this machine uses the
pre-existing `Private` vault for convenience, accepted risk.

---

## [2026-04-23] sync @ Hans Air M4

Track A (minimal): rename drift + guardrails pin bump, plus 4 requested new casks.

Brewfile (core):
  - rename: `cask "zen"` -> `cask "zen-browser"` (upstream renamed back)
  - added cask: wispr-flow (voice-to-text dictation)
  - added cask: font-ibm-plex-sans, font-ibm-plex-sans-hebrew, font-ibm-plex-serif

Guardrails:
  - bumped pin v0.3.7 -> v0.3.8 in run_onchange_after_claude-guardrails.sh.tmpl
    (release notes: https://github.com/dwarvesf/claude-guardrails/releases/tag/v0.3.8)

Not classified this session (deferred; surfaced in report only):
  - 22 untracked brew packages (duti, gitup, hub, jpeg-xl, libiconv, lume,
    markdown-oxide, ocaml, ollama, opencode, pandoc, pipx, playwright-cli,
    python@3.10, rclone, rust, shared-mime-info, subversion,
    the_silver_searcher, tldx, wireguard-tools, xcodegen, yarn, z, zsh)
  - 13 untracked casks (antigravity, calibre, chrysalis, codexbar, cursor,
    grandperspective, hyprnote, microsoft-auto-update, opencode-desktop,
    swiftdefaultappsprefpane, tana, tor-browser)
  - 1 new fish function: fisher.fish (Fisher plugin manager bootstrap)
  - 54 brew + 8 casks tracked-but-not-installed noise (never ran brew bundle here)
  - 25 VS Code extensions tracked-but-not-installed (user is on Cursor/Zed)

SSH backup status:
  - 2 of 2 on-disk keys still have no 1Password backup (action: `dotfiles ssh adopt`)

Earlier in same session (pre-sync):
  - feat(secrets): split Cloudflare API token from R2 credentials
  - feat(claude): sync personal PreToolUse hooks + Self-verification rules
    section into dotfiles modify_ overlay (below marker)
  - removed "# Self-verification rules" block from above-marker region of
    ~/.claude/CLAUDE.md since it was fragile against sync-claude-context.sh

---

## [2026-04-16] design session @ Mac mini

Big architectural session extending the core/local pattern and rewriting secret
loading. Full spec: [S-35](specs/S-35-local-pattern-and-lazy-secrets.md).
Test plan: [testing.md](testing.md).

Config includes:
  - fish: source ~/.config/fish/config.local.fish (new)
  - tmux: source-file -q ~/.config/tmux/tmux.local.conf (new)
  - git/ssh: already had native includes

dotfiles local CLI (new subcommand):
  - list / promote / demote / edit
  - dynamic completions for brew / cask / ext
  - auto-commits core changes; never commits .local files

Secrets rearchitected (lazy + Keychain):
  - Removed {{ onepasswordRead }} from secrets.fish.tmpl
  - New helper ~/.local/bin/secret-cache-read (Keychain first, op fallback)
  - dotfiles secret list now shows [cached]/[empty]
  - dotfiles secret refresh VAR (clear cache + re-fetch)
  - chezmoi apply no longer triggers any 1Password popups

Brewfile housekeeping:
  - Added 12 modern tools: tldr, sd, gping, atuin, lazygit, difftastic,
    kubectx, kubecolor, stern, opentofu, dive, buf
  - Removed deprecated taps: homebrew/bundle, homebrew/services
  - Fixed renames: zen-browser->zen, google-cloud-sdk->gcloud-cli
  - Fixed cask->formula: gifski, lume
  - Fixed formula->cask: nordvpn
  - Demoted to ~/.Brewfile.local: sentencepiece, tor-browser, lume, meetingbar
    (kept nordvpn, microsoft-edge, cloudflared, elixir in core per user)

Verification hooks:
  - Hostname tag in sync log entries (@ Mac mini)
  - Three new dotfiles doctor checks for .local pattern integrity

Audit:
  - git log --all scanned for hardcoded secrets: clean
  - No tokens, keys, or op:// values with plaintext ever committed

Post-session fixes (same day):
  - fix(doctor): exclude always-run scripts (R status) from drift count
  - fix(doctor): check login shell via dscl, not $SHELL (was misreporting after chsh)
  - chezmoi apply --force resolved Zed One Light/Dark drift
  - Default shell confirmed via dscl: /opt/homebrew/bin/fish (chsh worked previously,
    $SHELL was just stale in inherited processes)

Documentation refresh:
  - README.md: multi-machine positioning, .local pattern, lazy secrets section
  - docs/llm-dotfiles.md: added multi-machine sync + lazy secrets sections
    (stack-agnostic, shareable patterns)
  - CLAUDE.md: explicit design philosophy section (6 principles)

---

## [2026-04-16] sync

Config:
  - re-add Zed settings.json (removed agent_servers block, absorbed local edits)
  - chezmoi apply deployed all pending repo changes (fish config, starship, lib.sh, dotfiles CLI, completions, Claude config)

Brewfile:
  - added tap: hashicorp/tap
  - added brew: chezmoi, mdq, certbot, hashicorp/tap/vault, colima, docker, docker-compose, docker-credential-helper, sentencepiece
  - added cask: codex, chrysalis, disk-inventory-x, google-cloud-sdk, lunar, monitorcontrol, skype, zen-browser
  - skipped legacy packages already superseded (htop->btop, hub->gh, z->zoxide, pipx->uv, youtube-dl->yt-dlp, etc.)

VS Code extensions:
  - synced to match installed: added openai.chatgpt, removed 4 uninstalled (docker.docker, dwarvesf.md-ar-ext, ms-vsliveshare.vsliveshare, ocamllabs.ocaml-platform)

Fish functions:
  - tracked 4 unmanaged: keychain_env.fish, keychain_set.fish, op_env.fish, web3_env.fish

Secrets:
  - CLOUDFLARE_API_TOKEN already registered in secrets.toml, resolved from 1Password at apply time

---

## [2026-04-14] sync

Config:
  - re-add Zed settings.json (MCP server changes, local edits absorbed)

VS Code extensions:
  - add 5: docker.docker, dwarvesf.md-ar-ext, ms-vsliveshare.vsliveshare, ocamllabs.ocaml-platform, openai.openai-chatgpt-adhoc

Fish functions:
  - removed 5 orphaned standalone functions from machine (add-secret, dfe, dfs, list-secrets, rm-secret)  - consolidated into dotfiles subcommands

Brew/casks: deferred to next sync

---
