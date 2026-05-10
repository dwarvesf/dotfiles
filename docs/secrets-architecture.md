# Secrets architecture (the whole problem space)

The map above the spec chain. Read this first if you want to understand
**where** any future change to the secrets / keys / credentials surface
should go. For day-to-day usage, read [`1password.md`](1password.md).
For multi-machine setup, read
[`1password-multi-machine.md`](1password-multi-machine.md).

This doc is updated whenever a new spec lands. It does not duplicate the
manuals; it points at them.

---

## Why this doc exists

The repo has 13+ specs in the secrets surface (see [Spec-to-slice mapping](#spec-to-slice-mapping)).
Each spec closes a slice. Read in isolation, each is good. Read together,
they form a fragmented mosaic that nobody can hold in their head.

Symptoms before this doc existed:

- "We've discussed 1Password / multi-device several times, has it settled?"
- New spec proposals that overlap or contradict an existing one
- Forkers who read the spec chain and miss the manual, or vice versa
- Open questions buried as TODOs in commit messages or in `tasks.md`

This doc is the answer to "where does X belong?" It is **not** a how-to
(see manuals), **not** a runbook (see `operations/`), and **not** a spec
(see `specs/`). It's the index above all of those.

The discipline that backs this doc:

| Doc class | Path | Purpose |
|---|---|---|
| **Synthesis** (this doc) | `docs/secrets-architecture.md` | Map the whole problem space, catalog open questions |
| **Manual** | `docs/1password.md`, `docs/1password-multi-machine.md` | How to use what's built |
| **Spec** | `docs/specs/S-XX-*.md` | Single-slice design decision |
| **Decision (ADR)** | `docs/decisions/*.md` | Macro architectural choice (tooling, framework) |
| **Operations cookbook** | `docs/operations/YYYY-MM-*.md` | Author's record of applying a pattern (dated, personal) |

This synthesis doc is a **forkable framework artifact**. It must pass
`scripts/test-doc-discipline.sh` (placeholder-clean, no personal context).

---

## Threat model

Six adversary scenarios shape the design. Specs and manuals reference these.

| Adversary | What they can try | What protects against it |
|---|---|---|
| **Stolen primary device** | Grab a logged-in laptop, exfiltrate Keychain + 1P session | Disk encryption (FileVault), Keychain auto-lock on sleep, 1P MFA on new-device sign-in |
| **Stolen secondary (headless) device** | Grab a Mini, boot it, try to read Keychain | Login keychain locks at boot; ACL constraints on items written without `-A`; 1P SA token's vault scope (`Private` is unreadable to the SA) |
| **Malicious process running as the user** | Read env vars, pipe-tap stdin/stdout, exfiltrate `OP_SERVICE_ACCOUNT_TOKEN` | This is the accepted blast radius of [S-49](specs/S-49-dual-mode-op-via-fish-interceptor.md). SA scope minimization ([S-46](specs/S-46-three-vault-model-for-agent-infra-secrets.md)) limits damage. |
| **Network adversary on the wire** | Intercept secrets in transit between machines | SSH tunnels, agent forwarding (per-signature Touch ID), `op://` references resolved locally never sent over the wire |
| **Repository leak** (public mirror, accidental publish) | Read every committed file | No raw secrets ever committed; only `op://` references. Git history audited. `*.local` files gitignored and audit-checked. |
| **Compromised supply chain** (formula, plugin, agent) | Substitute a malicious binary that exfiltrates env | Out of scope for this design. Mitigated by macOS Gatekeeper and Homebrew bottle signing; see [`docs/decisions/`](decisions/) for tooling choices. |

A separate concern that has its own discipline (not adversary-shaped):

| Concern | Discipline |
|---|---|
| **Web3 signing key escape** | "No item that can produce a signature lives in any vault the SA can read." Rule documented in [`1password-multi-machine.md`](1password-multi-machine.md#web3-hardening-rule). Web3 keys live in hardware wallets or SE-backed wallet apps; never in 1P plaintext fields the SA can read. |

---

## Credential taxonomy

Six classes of credential live in the dotfiles surface. Each has different
storage, different lifecycle, different recovery story.

| Class | Where it lives at rest | How it reaches a process | Spec refs |
|---|---|---|---|
| **Service-account tokens** (read-only, vault-scoped) | 1P Private vault as a 1P item; cached value in Keychain on each machine | `OP_SERVICE_ACCOUNT_TOKEN` in shell env (set by [`secrets.fish`](../home/dot_config/fish/conf.d/secrets.fish.tmpl)) | [S-35](specs/S-35-local-pattern-and-lazy-secrets.md), [S-42](specs/S-42-service-account-agent-auth.md), [S-47](specs/S-47-agent-token-opt-in-wrapper.md), [S-49](specs/S-49-dual-mode-op-via-fish-interceptor.md), [S-51](specs/S-51-multi-machine-sa-access.md) |
| **Personal API tokens** (Cloudflare, OpenAI, etc.) | 1P vault as a 1P item; cached in Keychain | Var-by-var in shell env via the same `secrets.fish` mechanism | [S-35](specs/S-35-local-pattern-and-lazy-secrets.md), [S-43](specs/S-43-sync-secret-cache-visibility.md), [S-45](specs/S-45-secret-refresh-no-echo.md), [S-48](specs/S-48-secret-add-narrow-apply-scope.md) |
| **SSH private keys** | 1P SSH Key items; agent socket exposes them | `IdentityAgent` line in `~/.ssh/config`; per-signature Touch ID via 1P desktop | [S-38](specs/S-38-ssh-key-backup.md) |
| **Age encryption keys** | `~/.config/chezmoi/key.txt` (mode 600); backed up to 1P as a Document | Read by chezmoi at apply time when rendering encrypted files | [S-09](specs/S-09-age-encryption.md), [S-16](specs/S-16-age-encryption-guided-setup.md) |
| **Apply-time inline secrets** (gitconfig signing key, MCP server tokens, etc.) | 1P vault items | Resolved via `onepasswordRead` in `*.tmpl` files at `chezmoi apply` time, baked into rendered file on disk | Same secrets covered by S-35; the resolution path is different (path 3, see below) |
| **Web3 / signing material** (planned) | Hardware wallet or SE-backed wallet app; never in 1P-readable plaintext | Per-tx click on hardware wallet, or per-tx biometric in wallet app | None yet; rule documented in [`1password-multi-machine.md`](1password-multi-machine.md#web3-hardening-rule) |

Each class can choose a backend (1P, Bitwarden, age-encrypted file). Today
1P is the primary and age-encrypted is a secondary path; Bitwarden is a
parked alternative ([S-33](specs/S-33-bitwarden-secrets.md)).

---

## Device taxonomy

Five device classes interact with the secrets surface. The framework targets
classes 1-3; classes 4-5 are open territory.

| Device class | Role | GUI? | Biometric? | Status |
|---|---|---|---|---|
| **1. Primary Mac** ($PRIMARY) | Daily-driver laptop. The workspace where biometric works and 1Password desktop runs continuously. | Yes | Yes | Settled |
| **2. Secondary Mac** ($SECONDARY) | Second daily-driver workstation, often headless or operated mostly over SSH. S-51 + [S-53](specs/S-53-headless-mac-credential-pattern.md) target. | GUI optional under S-53 | Only when at the screen | Settled. SSH/mosh path closed by S-53 (System.keychain SA + per-machine SSH key). |
| **3. iOS SSH client** (Termius, Blink) | Phone or tablet, SSHing INTO the secondary. Cannot host 1P SSH agent. | iOS GUI | Yes (Face ID / Touch ID via Secure Enclave) | Mostly settled; `git push` from iOS-SSH session is an open option |
| **4. Linux secondary** (server) | A non-Mac headless box. Has no Keychain, no biometric, no 1P desktop. | No | No | **Open** |
| **5. Hardware wallet** (Ledger, Trezor) | Dedicated signing device for web3 keys. | Embedded (small screen + button) | Per-tx physical click | **Open / future** |

The S-51 model explicitly targets the macOS-to-macOS pair. Linux secondary
needs a different cache mechanism; hardware wallet is a different category
of device entirely.

---

## The credential paths

Each path is an independent way a credential reaches a process. They can
coexist; they do not share state. The S-51 design generalizes to:

| Path | Trigger | Approval | Scope | Failure mode |
|---|---|---|---|---|
| **1. 1P SSH agent** | `ssh`, `git push`, anything calling SSH | Touch ID per signature on the agent's host machine | Whatever SSH keys you have in 1P SSH Key items | Agent socket missing or unforwarded → key not found |
| **2. Interactive `op` (S-49 interceptor)** | Typing `op read ...` at fish prompt | Touch ID per call (token stripped) | Full-vault, biometric session view | Non-interactive subshell hits the bearer-auth branch instead |
| **3. chezmoi `onepasswordRead`** | `chezmoi apply` rendering `*.tmpl` | Touch ID per template | Whatever vaults the user can read | No GUI session = can't render; templates with `onepasswordRead` fail |
| **4. SA bearer token in env** | Any subprocess calling `op` with `OP_SERVICE_ACCOUNT_TOKEN` set | None (bearer) | SA-scoped vault only ($SA_SCOPED_VAULT) | Token not in env → fall-through to interactive path → may fail headlessly |
| **5. age-encrypted apply-time** | `chezmoi apply` rendering `encrypt = true` files | None at apply (key is already on disk) | Whatever the age recipient can decrypt | Age key missing or mismatched recipient |
| **6. Hardware wallet sign** (future) | Wallet app or CLI requesting a signature | Physical click on the device | Whatever keys are loaded on the device | Device unplugged or locked → signature fails |

Independence rule: SA token in env (path 4) never affects paths 1, 2, 3,
or 5. Each path can fail or succeed independently. See
[`1password-multi-machine.md`](1password-multi-machine.md#the-four-credential-paths)
for the full diagram of paths 1-4.

---

## Spec-to-slice mapping

Where every secrets-related spec sits in the model.

| Spec | Class touched | Path touched | Slice it closes | Status |
|---|---|---|---|---|
| [S-09](specs/S-09-age-encryption.md) | Age keys | Path 5 | Add age-encrypted secrets layer | done |
| [S-16](specs/S-16-age-encryption-guided-setup.md) | Age keys | Path 5 | Onboarding flow for age | done |
| [S-33](specs/S-33-bitwarden-secrets.md) | All 1P-backed classes | Path 2/3/4 | Bitwarden as alternative backend | planned |
| [S-35](specs/S-35-local-pattern-and-lazy-secrets.md) | Personal tokens, SA token | Path 4 (cache layer) | Lazy resolution + Keychain cache | done |
| [S-38](specs/S-38-ssh-key-backup.md) | SSH keys | Path 1 | Inventory, adoption (CLI → 1P), offline encrypted backup | done |
| [S-42](specs/S-42-service-account-agent-auth.md) | SA token | Path 4 | First attempt: auto-load token unconditionally | superseded by S-47 |
| [S-43](specs/S-43-sync-secret-cache-visibility.md) | All cached secrets | Path 4 (cache layer) | Surface registered-but-uncached in `dotfiles doctor` and sync | done |
| [S-45](specs/S-45-secret-refresh-no-echo.md) | All cached secrets | Path 4 (cache layer) | Stop leaking values into terminal scrollback during refresh | done |
| [S-46](specs/S-46-three-vault-model-for-agent-infra-secrets.md) | SA token | Path 4 (scope) | Vault tiering: SA reads scoped vault + optional Infras; never Private | proposed |
| [S-47](specs/S-47-agent-token-opt-in-wrapper.md) | SA token | Path 4 | Opt-in wrapper instead of auto-load | amended by S-49 |
| [S-48](specs/S-48-secret-add-narrow-apply-scope.md) | All cached secrets | Path 4 (tooling) | Scope `chezmoi apply` to single file in `secret add/rm` | done |
| [S-49](specs/S-49-dual-mode-op-via-fish-interceptor.md) | SA token | Path 2 + Path 4 | Auto-load + intercept interactive `op` to strip token | done |
| [S-51](specs/S-51-multi-machine-sa-access.md) | SA token | Path 4 (multi-machine) | `is-login` gate + remote Keychain seed via `dotfiles secret push` | done |
| **S-52** | (this synthesis doc) | meta | The map above the chain | done |
| [S-53](specs/S-53-headless-mac-credential-pattern.md) | SA token | Path 4 (backing store) | System.keychain replaces login.keychain for SSH/mosh path; per-machine SSH key for outbound git | done |
| [S-61](specs/S-61-batch-secret-cache-read.md) | All cached secrets | Path 4 (perf) | `secret-cache-read --batch` collapses N forks into one fish-startup call | done |
| [S-62](specs/S-62-secret-guard-pretooluse-hook.md) | All resolved values | Path 4 (anti-leak) | PreToolUse + Stop + PostToolUse hooks block secret-leaking outbound tool calls | done |
| [S-63](specs/S-63-secret-rotate-multi-host.md) | All registered secrets | Path 4 (rotation/seed) | Multi-host upsert: variadic targets + `--backing-store=login\|system` + `--local`; auto-detect delete-then-add; neg-cache cleanup | proposed |

Reading the table: most slices are about path 4 (the SA bearer cache) on
1P-backed classes. Paths 1, 3, 5 each have one or two specs; path 6 has
none yet. That uneven distribution is honest and matches where real-world
usage has driven design pressure.

---

## Open questions / catalog

The catalog forces the prioritization conversation rather than burying it
in scattered TODOs. Each entry: status, blocker (if any), next step.

### Q1. SA token rotation across N machines

**Status:** ~~open~~ closed by [S-63](specs/S-63-secret-rotate-multi-host.md) on 2026-05-10. `dotfiles secret push` now takes variadic targets (one or more SSH aliases plus optional `--local`), iterates sequentially, and emits a per-target verdict + summary. Auto-detect upsert (delete-then-add) handles seed + rotation cases on both `--backing-store=login` (default, S-51 path) and `--backing-store=system` (S-53 path). The "machine list as a config file" idea remains deferred (Q2) because N=2 today is fine with explicit args; revisit when the manual host list becomes painful.

### Q2. 3+ machines (and machine list as a first-class concept)

**Status:** open. The current model has $PRIMARY and $SECONDARY in mind.
**Blocker:** none; no third machine in use today.
**Next step:** when a third machine appears, generalize either via a
declared list (`secrets.toml` extension) or via discovery (e.g. Tailscale
device list).

### Q3. Linux secondary support

**Status:** open. macOS-only design today (Keychain, biometric, 1P desktop
agent).
**Blocker:** Linux has no equivalent of the login keychain in the same
shape; gpg-agent or libsecret-style backends differ.
**Next step:** scope a spec to define the Linux storage path. Probably a
file-based cache with mode 0600 + age encryption, falling back to
`pass`-style or `secret-tool` (libsecret).

### Q4. iOS-driven `git push` from $SECONDARY

**Status:** partially designed. Option A (per-iOS-app SE-bound key
registered with GitHub) is documented in
[`1password-multi-machine.md`](1password-multi-machine.md#what-breaks-from-ios)
but not implemented or scripted.
**Blocker:** none functional; just per-user setup.
**Next step:** when the author actually wants to push from iOS, generate
the Blink/Termius keys and add to GitHub. Document the recipe in
`docs/operations/`.

### Q5. Vault tiering ([S-46](specs/S-46-three-vault-model-for-agent-infra-secrets.md))

**Status:** proposed; structurally referenced everywhere but not yet
applied.
**Blocker:** activation requires moving items between vaults in 1P web
admin. Manual.
**Next step:** apply when an infra-cred workload (agent reading deploy
tokens) actually arrives. Not before.

### Q6. Web3 wallet integration

**Status:** rule documented; nothing implemented.
**Blocker:** no web3 work in flight in this repo today.
**Next step:** when web3 work begins, write a spec covering hardware-wallet
choice, wallet-vault separation, audit-trail expectations. Until then, the
discipline rule in `1password-multi-machine.md` is the entire design.

### Q7. Token leak detection

**Status:** open. Today `secret-cache-read` masks values, S-45 stopped
echoing during refresh, but if a token slips into a transcript or a
committed file, nothing detects it.
**Blocker:** detection costs ~a small spec.
**Next step:** consider a pre-commit hook that greps staged content for
`ops_*` or `op://` followed by `=`-style assignment leaks. Optional.

### Q8. SA usage audit

**Status:** open. 1P web admin logs SA reads. Nothing in this repo surfaces
unusual patterns.
**Blocker:** requires 1P API access (separate from SA token); cron-style
infra.
**Next step:** if SA scope grows or a leak is suspected, build a small
script that pulls the audit log via 1P API and diffs against expected
access patterns.

### Q9. Bitwarden alt-backend ([S-33](specs/S-33-bitwarden-secrets.md))

**Status:** planned. Forkers without 1P Business get partial value.
**Blocker:** Bitwarden CLI behavior differs from `op`; abstraction layer
needed.
**Next step:** when a forker without 1P actually files an issue, design
the abstraction. Until then, parked.

### Q10. Auto-login on $SECONDARY as codified preference vs operational

**Status:** moot as of 2026-05-07; **resolved differently as of 2026-05-08**.
Empirical test (iOS mosh against a headless Mac with auto-login enabled and
the GUI logged in continuously) showed that auto-login does **not** make
the login keychain readable from SSH/mosh sessions: macOS holds keychain
unlock state per Security Session, not per user. The original framing of
this question — "should we codify the auto-login choice?" — assumed
auto-login was a working mitigation. It isn't. See
[S-51 errata 2026-05-07](specs/S-51-multi-machine-sa-access.md#errata-2026-05-07).
**Resolution:** [S-53](specs/S-53-headless-mac-credential-pattern.md) picks
System.keychain as the SA backing store (no per-session unlock) and adds a
per-machine SSH-key recipe so outbound `git` works without agent forwarding.
Auto-login is no longer load-bearing for the SSH/mosh path under S-53.

---

## When to commission a new spec vs an operations cookbook

A common slip-up is turning a personal rollout into a "spec" or, worse, a
spec into a cookbook. The discipline:

```
                    ┌───────────────────────────────────┐
                    │ I want to change how the secrets  │
                    │ surface BEHAVES (gate, helper,    │
                    │ ACL, scope, …)                    │
                    └───────────────┬───────────────────┘
                                    │
                                    ▼
                            ┌───────────────┐
                            │  WRITE A SPEC │
                            │  S-XX         │
                            └───────────────┘

                    ┌───────────────────────────────────┐
                    │ I'm APPLYING a pattern to my own  │
                    │ machines, with real hostnames /   │
                    │ vault paths / item names          │
                    └───────────────┬───────────────────┘
                                    │
                                    ▼
                          ┌─────────────────────┐
                          │  WRITE A COOKBOOK   │
                          │  operations/YYYY-MM │
                          └─────────────────────┘

                    ┌───────────────────────────────────┐
                    │ I want to record HOW I made a     │
                    │ macro choice (which framework,    │
                    │ which protocol, why)              │
                    └───────────────┬───────────────────┘
                                    │
                                    ▼
                            ┌──────────────┐
                            │  WRITE AN ADR│
                            │  decisions/  │
                            └──────────────┘

                    ┌───────────────────────────────────┐
                    │ I want to update the MAP of the   │
                    │ whole problem space               │
                    └───────────────┬───────────────────┘
                                    │
                                    ▼
                            ┌───────────────────┐
                            │  EDIT THIS DOC    │
                            │  +/- catalog item │
                            └───────────────────┘
```

Tests:

- If the artifact contains a real hostname or a real `op://` path, it's a
  cookbook. Move it to `operations/` and use placeholders in any spec.
- If the artifact is dated, it's a cookbook or a sync-log entry, never a
  spec.
- If the artifact only points at other docs without proposing a behavioral
  change, it's a synthesis-doc edit, not a spec.
- If the artifact would still be useful in 2 years with the same framework,
  it's a spec or ADR. If it's only useful for one rollout, it's a cookbook.

---

## Settling status — answer to "is this done?"

**Settled (won't need another spec without a new use case):**

- Single-machine SA token + Keychain cache + dual-mode `op` (S-35 → S-49)
- Multi-machine SA token via `is-login` gate + `secret push` + `-A` ACL (S-51)
- SSH key inventory / adoption / backup (S-38)
- age encryption layer for chezmoi-managed files (S-09, S-16)
- Tooling hygiene around secret manipulation (S-43, S-45, S-48)

**Partially settled (designed, not deployed):**

- Vault tiering (S-46): structurally referenced, not applied
- Bitwarden alternative (S-33): planned, not designed in detail

**Open (no spec yet, see catalog):**

- Token rotation across N machines (Q1)
- 3+ machines as a first-class concept (Q2)
- Linux secondary (Q3)
- iOS-driven `git push` automation (Q4)
- Web3 / hardware wallet integration (Q6)
- Token leak detection (Q7)
- SA usage audit (Q8)
- ~~Auto-login preference codification (Q10)~~ — moot as of 2026-05-07; resolved differently 2026-05-08 by [S-53](specs/S-53-headless-mac-credential-pattern.md) (System.keychain SA + per-machine SSH key).

The honest answer to "have we settled it?" is: **the macOS-to-macOS
console-to-console slice is settled. The macOS-to-macOS SSH/mosh slice is
settled as of 2026-05-08 via [S-53](specs/S-53-headless-mac-credential-pattern.md).**
**Everything outside macOS-to-macOS is catalogued, not solved.** Any
session that wants to reduce the open list should pick one item from the
catalog and write a spec.

---

## Maintenance contract

When a new spec lands in the secrets surface:

1. Add a row to [Spec-to-slice mapping](#spec-to-slice-mapping).
2. Move any item from [Open questions](#open-questions--catalog) to
   "settled" in [Settling status](#settling-status--answer-to-is-this-done) if
   the spec closes it.
3. If the spec adds a new credential class, device class, or path, update
   the relevant taxonomy section.
4. If the spec changes the threat model (new adversary surface, new
   defense), update the [Threat model](#threat-model) table.
5. Run `./scripts/test-doc-discipline.sh` to confirm placeholder cleanliness.

When an operations cookbook lands at `docs/operations/YYYY-MM-*.md`:

- Optionally add a row to the [Settling status](#settling-status--answer-to-is-this-done)
  pointing at it as evidence the pattern was actually applied.
- Cookbooks DO contain personal context; don't add them to the discipline
  test's framework list.

---

## See also

- [`1password.md`](1password.md) — single-machine model + day-to-day commands (the manual)
- [`1password-multi-machine.md`](1password-multi-machine.md) — multi-machine extension (the manual)
- [`operations/2026-05-mini-sa-seed.md`](operations/2026-05-mini-sa-seed.md) — example operations cookbook (author's specific S-51 rollout)
- [`operations/2026-05-10-sa-rotation-air-mini.md`](operations/2026-05-10-sa-rotation-air-mini.md) — author's specific S-63 rollout (2026-05-10 SA rotation across Air + Mini that triggered the spec)
- [`tasks.md`](tasks.md) — chronological completed-spec index
- [`sync-log.md`](sync-log.md) — per-machine sync history
- [`decisions/`](decisions/) — ADRs (why chezmoi, why fish, why 1P, etc.)
- [`specs/`](specs/) — all spec files indexed in the [Spec-to-slice mapping](#spec-to-slice-mapping) above
- [`scripts/test-doc-discipline.sh`](../scripts/test-doc-discipline.sh) — the framework-vs-personal contract test
