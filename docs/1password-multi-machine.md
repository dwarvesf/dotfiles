# 1Password multi-machine access

Companion to [`docs/1password.md`](1password.md). Read that one first; it covers
the single-machine model. This one covers what changes when you have **two or
more daily-driver machines** sharing the same dotfiles, and what's possible
when one of those "machines" is an iOS SSH client (Termius, Blink).

If you only read one section, read **[Mental model](#mental-model)** then
**[Per-environment state matrix](#per-environment-state-matrix)**. Everything
else is depth on demand.

---

## Variables in this doc

This is a **forkable framework pattern**, not a personal cookbook. The doc
uses placeholder names; substitute when you apply the pattern. The author's
specific application (with real hostnames, vault paths, SSH aliases) lives
in [`docs/operations/2026-05-mini-sa-seed.md`](operations/2026-05-mini-sa-seed.md).

| Placeholder | Meaning | Example you might use |
|---|---|---|
| `$PRIMARY` | Daily-driver Mac with a continuous GUI session. The machine where biometric works and 1Password desktop runs. | A laptop you carry. |
| `$SECONDARY` | Second daily-driver Mac, also a workstation, but operated mostly over SSH. The machine that needs SA token in env without biometric. | A Mac mini in your office. |
| `$SECONDARY_SSH_ALIAS` | The SSH config alias that resolves to `$SECONDARY` for the user account that owns the dotfiles. | `secondary-host` |
| `$SA_REF` | The `op://Vault/Item/field` reference to your service-account token's credential. | `op://YourVault/agent-token/credential` |
| `$SA_SCOPED_VAULT` | The 1Password vault the service account is allowed to read (per [S-46](specs/S-46-three-vault-model-for-agent-infra-secrets.md) tiering). | `Agents` |

The mental model and gate flow are universal. Only the names change per setup.

---

## TL;DR

- The dotfiles already define a clean **dual-mode `op`** model on a single
  machine ([S-49](specs/S-49-dual-mode-op-via-fish-interceptor.md)):
  subprocesses use a bearer SA token from env, interactive fish strips it
  and uses biometric.
- Extending to a second machine is **not** about replicating $PRIMARY's setup
  blindly. It's about understanding which credential paths are local-state-
  dependent and which are user-presence-dependent, then arranging the gates
  so SSH-driven flows don't fail.
- Four credential paths exist. They're independent. Don't conflate them.
- iOS SSH clients (Termius, Blink) work fine for read-shaped flows; the only
  gap is outbound `git push` from $SECONDARY, and it's solvable per-client
  when you actually need it.
- Caching the SA token does not weaken web3 signing security. The two systems
  are architecturally orthogonal **as long as no signing material lives in
  any vault the SA can read**. That's the discipline rule.

---

## Mental model

Three orthogonal questions decide what happens when any tool tries to use a
1Password-backed credential:

1. **Which path is the tool on?** (1P SSH agent, S-49 op interceptor,
   chezmoi `onepasswordRead`, or SA bearer token in env.)
2. **What's the user-presence state?** (GUI session active and unlocked, vs.
   SSH-only with no GUI.)
3. **What's the local cache state?** (Keychain seeded vs. not, Keychain
   unlocked vs. locked, Keychain ACL permissive vs. session-bound.)

Failures happen when a path requires presence/cache state that the current
environment can't provide. The job of this doc is to lay out which path
needs what, so you can pick the right one per task and not be surprised.

---

## The four credential paths

Each path has its own auth mechanism, its own approval surface, and its own
failure mode. They run in parallel; they do not share state.

### Path 1: 1Password SSH agent

```
~/.ssh/config:
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
$SSH_AUTH_SOCK = that socket
```

**Triggered by**: every `ssh`, `scp`, `rsync`, `git push` (when remote uses ssh).

**Approval**: 1P desktop pops Touch ID per signature, on the machine where
the agent runs. Always.

**Cross-machine story**: from $SECONDARY, you can use $PRIMARY's agent via
SSH agent forwarding (`ForwardAgent yes`). Touch ID still happens **on
$PRIMARY** because that's where the agent and your physical screen are.

**SA token in env**: irrelevant. Different binary, different socket.

### Path 2: Interactive `op` (S-49 interceptor)

```fish
function op
    if status is-interactive
        env -u OP_SERVICE_ACCOUNT_TOKEN command op $argv  # strips SA token
    else
        command op $argv
    end
end
```

**Triggered by**: typing `op read ...` at a fish prompt (any interactive fish).

**Approval**: drops the SA token, calls real `op`, falls back to 1P desktop's
biometric session. Touch ID popup, full-vault view.

**Failure mode**: on a machine without a usable GUI session (SSH-only into
$SECONDARY), the biometric path can't run. Typed `op read` from $SECONDARY's
fish prompt over SSH **fails silently with empty output**. Workaround:
`command op read ...` to bypass the function and use bearer auth.

### Path 3: chezmoi apply-time (`onepasswordRead`)

```jinja
# in *.tmpl files
{{ onepasswordRead "op://Vault/SomeItem/credential" }}
```

**Triggered by**: `chezmoi apply` rendering any template with
`onepasswordRead`. Used by `dot_gitconfig.tmpl`,
`dot_config/zed/settings.json.tmpl`, and similar.

**Approval**: every render call goes through 1P desktop biometric.

**Failure mode**: same as Path 2. No GUI = no apply. Run `chezmoi apply` and
`dotfiles sync` from $PRIMARY or while physically at $SECONDARY, never over
a headless SSH session.

### Path 4: SA bearer token in env

```
OP_SERVICE_ACCOUNT_TOKEN=ops_... in shell env
subprocess `op read op://Vault/...` → bearer auth → returns secret
```

**Triggered by**: any non-fish subprocess (`bash -c 'op read ...'`, scripts,
Claude Code's Bash tool, agents) where the env var is in scope.

**Approval**: none. That's the design.

**Scope**: read-only, scoped to $SA_SCOPED_VAULT. Never includes the vault
that holds the SA token's own credential (defense in depth, [S-46](specs/S-46-three-vault-model-for-agent-infra-secrets.md)).

**Failure mode**: token not in env → bearer auth has nothing to send → falls
back to interactive auth → fails over SSH. The S-51 design fixes this for
the SSH-into-$SECONDARY case.

### Independence diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Path 1: 1P SSH agent socket                                        │
│      ↳ used by ssh / git push                                       │
│      ↳ Touch ID per signature                                       │
│                                                                     │
│  Path 2: fish op interceptor (interactive)                          │
│      ↳ used when YOU type op at fish prompt                         │
│      ↳ Touch ID per call                                            │
│                                                                     │
│  Path 3: chezmoi onepasswordRead (apply-time)                       │
│      ↳ used by chezmoi apply / dotfiles sync                        │
│      ↳ Touch ID per template                                        │
│                                                                     │
│  Path 4: SA bearer token in env                                     │
│      ↳ used by subprocess scripts / agents                          │
│      ↳ no approval, narrow scope                                    │
│                                                                     │
│  These DO NOT share state. SA token in env never affects paths 1-3. │
│  Each path can fail or succeed independently.                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## The 3 gates at fish login

Path 4 is the only path that depends on local cache state. Three gates fire
in sequence at fish login to decide whether the SA token ends up in env.

```
fish session starts
      │
      ▼
┌─────────────────────┐
│ GATE 1: status      │ ← `is-login` (post-S-51); was `is-interactive`
│ filter passes?      │
└──────────┬──────────┘
           │
   yes ────┴──── no → block skipped, token stays empty
           │
           ▼
┌─────────────────────┐
│ GATE 2: Keychain    │ ← per-machine state. Login keychain on this Mac.
│ entry hit?          │
└──────────┬──────────┘
           │
   yes ────┴──── no → fall through to op read
           │              │
           ▼              ▼
       token in       ┌─────────────────────┐
       env. DONE.     │ GATE 3: biometric   │ ← needs GUI session
                      │ unlock available?   │
                      └──────────┬──────────┘
                                 │
                          yes ───┴─── no → token stays empty, FAIL
                                 │
                                 ▼
                          Touch ID popup,
                          op read succeeds,
                          Keychain seeded,
                          token in env
```

Gate 2 has two sub-conditions you'll trip if you're not careful:

**Sub-condition A — login keychain locked.** Even when the entry exists, the
keychain must be **unlocked**. The keychain unlocks automatically on GUI
login; on SSH key auth, it stays in whatever state it was in. A reboot
without a GUI login leaves the cache inert.

**Sub-condition B — narrow ACL.** macOS binds each Keychain item's ACL to
the originating process context. An entry written from a GUI session is
readable by GUI-session processes by default, but an SSH-context read may
be denied silently. The fix is to write entries with `-A` (allow any
application the user runs to read it). Both `secret-cache-read` and
`dotfiles secret push` pass `-A`. If you ever seed an entry with a
hand-rolled `security add-generic-password` and forget `-A`, you'll see
this exact symptom: the entry exists in `dump-keychain` output, but
SSH-context reads return empty, and `secret-cache-read` falls through to
`op read` and triggers a biometric popup. Same blast radius as the env-var
model (any process the user runs can read), so `-A` is the right default.

---

## Per-environment state matrix

| Environment | Gate 1 | Gate 2 | Gate 3 | Result |
|---|---|---|---|---|
| $PRIMARY, GUI terminal (steady state) | pass | hit | n/a | token in env, all paths work |
| $PRIMARY, first-ever fish login | pass | miss | available | one Touch ID popup, then steady |
| $SECONDARY, at GUI keyboard | pass | hit (post-seed) | available | token in env, biometric works for Path 2/3 |
| $SECONDARY, SSH from $PRIMARY after S-51 | pass (login) | hit | n/a | token in env, Path 4 works, Path 2/3 fail |
| $SECONDARY, SSH from iOS (Termius/Blink) after S-51 | pass (login) | hit | n/a | identical to SSH-from-$PRIMARY case |
| $SECONDARY, SSH right after reboot, no GUI login since | pass (login) | **locked** | unavailable | token empty, ops scripts fail until someone unlocks Keychain |

The last row is the headless-reboot edge case. Three mitigations are in
[Multi-machine extension](#multi-machine-extension) below.

---

## Multi-machine extension

### Why "replicate the $PRIMARY setup" isn't quite right

The $PRIMARY-side setup assumes interactive fish at first login (which seeds
the Keychain) and a GUI session at all times (which keeps it unlocked).
$SECONDARY is a daily driver but spends most of its time accepting SSH
connections, not GUI sessions. Two failure modes $PRIMARY doesn't have:

1. **First fish login on $SECONDARY happens via SSH**, which is non-interactive
   when invoked as `ssh user@host '<cmd>'`. Gate 1 (`is-interactive`) fails.
   Even when it's interactive (`ssh user@host` with a TTY), Gate 3 (biometric)
   isn't available, so the seed step fails. Result: Keychain never gets
   seeded, all subsequent SSH sessions hit Gate 2 misses.

2. **Login keychain locks at reboot** until something unlocks it. SSH key
   auth doesn't unlock it. So even after seeding, a reboot without a GUI
   login leaves the cache inert.

### The fix, in two parts

**Part 1 — seed once from $PRIMARY**:

```fish
# from $PRIMARY (where biometric works)
dotfiles secret push <VAR_NAME> $SECONDARY_SSH_ALIAS
```

The helper reads the value locally via `op read` (biometric on $PRIMARY,
full-vault scope), pipes it over SSH stdin, writes the remote login keychain
with `-A` ACL, then verifies by reading back. One-time per token value;
re-run for rotation. The literal command for the author's specific setup is
in the operations cookbook (link at the bottom).

**Part 2 — change Gate 1 from `is-interactive` to `is-login`**:

`is-login` is true for both:

- interactive sessions (the daily case)
- non-interactive SSH login shells (`ssh host '<cmd>'` invocations)

It's still false for `fish file.fish` invocations (correct: scripts shouldn't
trigger secret loads).

After both changes, the matrix above holds and `op read` from any subprocess
on $SECONDARY works the same as on $PRIMARY.

### Boot-time keychain lock

> **Resolved by [S-53](specs/S-53-headless-mac-credential-pattern.md) (2026-05-08).**
> Login keychain unlock state is per-Security-Session, not per-user, so
> SSH/mosh sessions see a locked keychain regardless of console GUI state
> (originally documented in [S-51 errata 2026-05-07](specs/S-51-multi-machine-sa-access.md#errata-2026-05-07)).
> S-53 moves the SA token to System.keychain, which has no per-session
> unlock requirement, and adds a per-machine SSH-key recipe so outbound
> `git` over SSH works without agent forwarding (which mosh strips). The
> three options in the table below are now of historical interest only —
> none of them actually fix SSH/mosh access. Apply S-53 instead.

Three options, in order of preference for a personal home setup:

| Option | Effort | Trade-off |
|---|---|---|
| **Walk over and log in at $SECONDARY's screen after each reboot** | zero | Manual ritual. Fine if reboots are rare and you're often near $SECONDARY. |
| **Auto-login the user at boot** (System Settings → Users & Groups) | 30s | Login keychain unlocks automatically. Anyone who power-cycles $SECONDARY gets a logged-in GUI session. Acceptable for a home machine behind a locked door. |
| **Move SA token to a separate, never-locking keychain** | ~1h, more dotfiles surface | Most flexible. Probably overkill for personal use. Document if you go here. |

This is an **operational** decision, not a dotfiles change. The S-51 patch
fixes the seed, gate, and ACL problems; the lock issue is between you and
your hardware.

### Cross-machine drift discipline

A token rotation on $PRIMARY (via `dotfiles secret refresh`) updates
$PRIMARY's Keychain. $SECONDARY's Keychain still holds the old value.
Re-seed manually with `dotfiles secret push`. If rotation becomes frequent,
build a `dotfiles secret push --all-machines` helper; today, manual is fine.

---

## iOS SSH (Termius, Blink)

iOS SSH clients can connect *into* $SECONDARY. They cannot host a 1Password
SSH agent: that feature is desktop-only on macOS, Windows, Linux. So flows
that depend on Path 1 (the 1P SSH agent) need a different approach when the
SSH session originates from iOS.

### What works unchanged from iOS

After S-51 lands on $SECONDARY:

- **Path 4 reads** (`op read op://...` from any script or bash one-liner):
  same as from $PRIMARY. $SECONDARY's local state determines the outcome,
  not the SSH origin.
- **Status checks, log tails, daemon kicks, agent inspection**: anything
  that doesn't shell back out to ssh/git.

### What breaks from iOS

- **`git push` from $SECONDARY**: needs an SSH agent to sign the GitHub
  key. No 1P agent on iOS to forward, so the default $PRIMARY recommendation
  (`ForwardAgent yes`) doesn't apply. Three options:

| Option | Approach | Per-action approval? |
|---|---|---|
| **A. iOS-app SE-bound SSH key** | Generate an ed25519 key in Blink (or Termius), bound to iOS Secure Enclave. Add public key to GitHub. Forward agent from iOS to $SECONDARY. | Face ID / Touch ID on iPhone per signature. Same security model as 1P SSH agent. |
| **B. $SECONDARY-resident SSH key** | `ssh-keygen` on $SECONDARY, public key in GitHub. | None. Ambient. **Bad** for personal repos. |
| **C. Don't push from iOS sessions** | Treat iOS SSH as inspect-only. Push from a Mac. | n/a |

Default to C; add A the first time you genuinely want to push from a phone.
Don't pre-build it.

- **Path 2 typed `op read`**: the interceptor strips the SA token and tries
  biometric. $SECONDARY has no GUI; popup never reaches you. Workaround:
  `command op read op://...` to bypass the interceptor and use the cached
  SA token directly. Yields the SA-scoped view, fine for ops-shaped lookups.

- **Path 3 `chezmoi apply` / `dotfiles sync`**: don't run these from iOS SSH.
  They expect biometric in multiple places. Run from a Mac.

### iOS SSH support summary

| iOS-driven workflow | Verdict |
|---|---|
| Tail logs, check status, kick a daemon | works |
| Script that does `op read op://$SA_SCOPED_VAULT/...` | works |
| Type `op read` ad-hoc at $SECONDARY's prompt | use `command op read ...` |
| `git push` from $SECONDARY | needs Option A (iOS SE key in GitHub) or skip |
| `chezmoi apply`, `dotfiles sync` | run from a Mac instead |

---

## Web3 hardening rule

Caching the SA token (Path 4) does **not** weaken web3 signing security. The
two systems are architecturally orthogonal **as long as no signing material
lives in any vault the SA can read**. The reasoning:

1. Web3 signing keys live in:
   - hardware wallet (Ledger, Trezor) → physical button per tx
   - Secure-Enclave-backed wallet app (Frame, Rabby with biometric) →
     Touch ID per tx
   - 1Password's wallet integration → Touch ID via 1P desktop biometric
2. Producing a signature requires *capability* (a wallet device or process
   that can sign), not just *knowledge* (a string in a vault). The SA token
   grants knowledge, not capability.
3. Path 1 (the 1P SSH agent) already proves the model works. SSH key
   signatures use a 1P-mediated agent that demands per-action Touch ID,
   uninfluenced by the SA token in env. Web3 signing follows the same
   pattern with a different agent (the wallet app or hardware device).

The single failure mode where SA cache *does* threaten web3 is when **raw
signing material is stored as plaintext in an SA-readable vault**. Then
"reading the vault" and "signing a transaction" become the same operation.
Don't do this.

### Discipline rule (codify and enforce)

> **No item that can produce a signature lives in any vault the SA can read.**
> 1Password may hold *labels*, *recovery hints*, or *public addresses* for
> wallet items. It must not hold seeds, private keys, or keystore JSONs in
> SA-readable vaults. Hardware wallet seed phrases live on paper, in a safe,
> never in 1Password.

This rule applies whether or not $SECONDARY is in the picture, whether or
not iOS SSH is in the picture. It's the contract that lets you keep the
SA cache convenience without putting your future signing keys at risk.

The S-46 vault tiering proposal already supports this rule structurally
(SA reads $SA_SCOPED_VAULT and optionally an `Infras` tier; never
`Private`; never a future `Wallet`). When you onboard web3 keys, codify
a `Wallet` vault that is explicitly outside SA scope.

---

## See also

- [`secrets-architecture.md`](secrets-architecture.md) — the **whole-surface map**: credential × device × path matrix, spec-to-slice index, threat model, open-questions catalog. Read this if you're deciding where a future secrets-related change should go.
- [S-35](specs/S-35-local-pattern-and-lazy-secrets.md) — lazy resolution + Keychain cache
- [S-42](specs/S-42-service-account-agent-auth.md) — original SA auto-load
- [S-46](specs/S-46-three-vault-model-for-agent-infra-secrets.md) — vault tiering proposal
- [S-49](specs/S-49-dual-mode-op-via-fish-interceptor.md) — current dual-mode design
- [S-51](specs/S-51-multi-machine-sa-access.md) — this multi-machine extension (the spec-shaped change list)
- [`docs/1password.md`](1password.md) — single-machine model and day-to-day commands
- [`docs/operations/2026-05-mini-sa-seed.md`](operations/2026-05-mini-sa-seed.md) — author's specific application of this pattern (real hostnames, real `op://` refs)
