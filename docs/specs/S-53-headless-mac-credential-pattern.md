---
id: S-53
title: Headless Mac credential pattern (System.keychain SA + per-machine SSH key for SSH/mosh)
type: feature
status: done
date: 2026-05-08
extends: S-51
---

# S-53: Headless Mac credential pattern for SSH/mosh

Closes the [S-51 errata 2026-05-07](S-51-multi-machine-sa-access.md#errata-2026-05-07)
"Fix space" question by picking option 2 (System.keychain) for the SA token
and adding a complementary per-machine SSH-key recipe for outbound git over
SSH. The result: a headless Mac is fully self-sufficient for `op` and `git`
over any SSH transport, including iOS mosh, without depending on the
Security-Session-bound login keychain or on agent forwarding.

## Variables used in this spec

This is a framework spec. Substitute placeholders for your own setup; the
author's specific application is recorded in the sync-log, not here.

| Placeholder | Meaning | Example |
|---|---|---|
| `$PRIMARY` | Daily-driver Mac with a continuous GUI session, running 1Password desktop. | A MacBook you carry. |
| `$SECONDARY` | Headless or mostly-headless Mac, operated over SSH from `$PRIMARY` and over mosh from an iOS client. | A Mac mini in a back room. |
| `$iOS_CLIENT` | Mobile SSH client (Blink, Termius, Prompt) used to reach `$SECONDARY` over mosh. | iPhone or iPad. |
| `$SA_REF` | `op://Vault/Item/credential` reference to the service-account token minted for `$SECONDARY`. | `op://Agents/secondary-sa/credential` |
| `$GH_KEY_REF` | `op://Vault/Item` reference to the SSH key item generated inside 1Password for `$SECONDARY`. Item must live in a vault visible to whichever 1P session you're driving from. | `op://Agents/secondary-github` |
| `$GH_KEY_PATH` | Where the private key lands on `$SECONDARY`. | `~/.ssh/id_ed25519_github` |

## Problem

[S-51](S-51-multi-machine-sa-access.md) widened `secrets.fish`'s gate to
`is-login` so SSH and mosh sessions on `$SECONDARY` would load secrets, and
added `dotfiles secret push` to seed the remote Keychain. The
[2026-05-07 errata](S-51-multi-machine-sa-access.md#errata-2026-05-07)
recorded that the implementation is correct but the **backing store
assumption is wrong**: the login keychain holds unlock state per Security
Session, not per user. SSH and mosh sessions run in different Security
Sessions than the console GUI, so the login keychain is locked there even
when the user has been logged in at the screen for days.

The errata listed four fix candidates and deferred the choice. This spec
picks one, plus solves a parallel gap that becomes visible once the SA
side works: outbound `git` from `$SECONDARY` was relying on agent
forwarding from `$PRIMARY`, which mosh strips on session reconnect and
which iOS clients cannot recreate.

## Design

### Decision 1: System.keychain for the SA token

System.keychain (`/Library/Keychains/System.keychain`) is in the keychain
search list of every session on the host (verified via `security
list-keychains` from a non-interactive ssh) and has no per-session unlock
requirement. Items planted there with `-A` are readable by the same UID
from any Security Session.

| Backing store | SSH/mosh readable? | Sudo to write? | Per-session unlock? |
|---|---|---|---|
| login.keychain (S-51 default) | No (locked) | No | Yes |
| **System.keychain (this spec)** | **Yes** | **Yes** | **No** |
| Plain file `chmod 600` (errata candidate 1) | Yes | No | No |
| LaunchAgent + Unix socket (errata candidate 3) | Yes | No (per-user agent) | No |
| 1Password Connect (errata candidate 4) | Yes | Sudo if Docker on host | No |

System.keychain wins for "least new moving parts": no agent process to
own, no Connect server to operate, and `secret-cache-read` already calls
`security find-generic-password` without a `-k` flag, so it inherits the
search list automatically. The `-A` ACL has the same blast radius as
S-51's login-keychain entry: any process the user runs can read.

### Decision 2: Per-machine SSH key for `git`, not agent forwarding

`$PRIMARY` historically had `ForwardAgent yes` for `$SECONDARY`. Mosh
breaks this:

- Mosh establishes a UDP session and proxies stdio. It does not forward
  Unix sockets. `$SSH_AUTH_SOCK` is not set on the remote.
- `$iOS_CLIENT`'s SSH agent (Blink's keys, Termius's keys) is a separate
  agent from `$PRIMARY`'s 1Password SSH agent. Even if the iOS client
  could forward, the keys it holds are different.

So `git@github.com` from `$SECONDARY` would work from `$PRIMARY` ssh but
fail from `$iOS_CLIENT` mosh. Symmetric per-machine credentials remove
this asymmetry: `$SECONDARY` carries its own ed25519 key whose public
half is registered with the upstream (GitHub, Gitea, etc.). Every
SSH transport works the same way.

| | Agent forwarding from `$PRIMARY` | Per-machine key on `$SECONDARY` |
|---|---|---|
| Works over plain ssh | Yes | Yes |
| Works over mosh | No (no socket) | Yes |
| Works from `$iOS_CLIENT` | No (different agent) | Yes |
| Blast radius if `$PRIMARY` compromised | Forwarded keys reachable on `$SECONDARY` for session lifetime | None — `$SECONDARY` has its own credentials |
| Blast radius if `$SECONDARY` compromised | Per-machine key only | Per-machine key only |
| Setup cost | Already done | One-time generate + register |

### Decision 3: Generate the SSH key inside 1Password, transport in OpenSSH format

Two non-obvious quirks:

1. `op` cannot import an existing private key (CLI 2.x rejects all import
   paths for SSH key material). Keys must be generated inside 1P with
   `--ssh-generate-key`.
2. `op read "op://.../private key"` returns **PKCS#8** by default, which
   OpenSSH refuses to load with `Load key: invalid format`. The
   `?ssh-format=openssh` query parameter forces the canonical OpenSSH
   format. Use it whenever piping to disk.

### Decision 4: Robust transport for piped content

Two transport patterns came out of this work; one for binary/sensitive
content, one for text config:

- **base64 round-trip** for binary or sensitive content over fish→ssh→fish
  pipes. SSH preserves bytes byte-for-byte, but multiple shell parse
  layers can swallow or transform escape sequences and corrupt PEM blocks.
  base64 output is `[A-Za-z0-9+/=\n]` only; no shell metacharacters.
  ```
  <source> | base64 | ssh $host 'base64 -d > /target/path'
  ```
- **Single-quoted multi-line strings via stdin pipe** for plain text
  newlines. Fish preserves newlines literally inside `'...'`; `printf
  "...\n..."` is unreliable across the fish→ssh→fish boundary.
  ```
  echo 'line1
  line2' | ssh $host 'cat >> /target/file'
  ```

Both avoid the `\n`-escape-mangling failure mode hit during this work.

## Implementation steps (manual, not codified in dotfiles)

This spec records what to do; the dotfiles repo does not yet automate it.
See [Future work](#future-work).

### A. Mint a per-machine SA token

In the 1P web admin (Developer Tools → Service Accounts), create one SA
per `$SECONDARY` instance. Grant only the vault(s) `$SECONDARY` reads.
Note: SA tokens are scoped to a single 1P account; you cannot grant a
business-account SA access to a personal-account vault, or vice versa.

### B. Plant the SA token in `$SECONDARY`'s System.keychain

```fish
# from $SECONDARY (interactive, after sshing in)
read --silent --prompt-str="Paste SA token: " TOKEN
sudo security add-generic-password \
  -a $USER \
  -s OP_SERVICE_ACCOUNT_TOKEN \
  -w $TOKEN \
  -A \
  -T /usr/bin/security \
  -T /opt/homebrew/bin/op \
  /Library/Keychains/System.keychain
set -e TOKEN
```

`-A` is the load-bearing flag. `-T` is belt-and-suspenders for explicit
binary trust; `-A` makes it redundant but harmless.

### C. Generate a per-machine SSH key inside 1Password

```fish
op item create \
  --category=ssh-key \
  --title=$ITEM_TITLE \
  --ssh-generate-key=ed25519 \
  --vault=$VAULT_NAME
```

**Gotcha:** if you write `--ssh-generate-key --vault=...`, the parser
consumes `--vault=...` as the value of `--ssh-generate-key` and errors
with "must be Ed25519 or RSA." Always pass `=ed25519` explicitly or
reorder so `--ssh-generate-key` is last.

### D. Plant the private key on `$SECONDARY` in OpenSSH format

```fish
# from any host with op CLI access to $GH_KEY_REF
op read "$GH_KEY_REF/private key?ssh-format=openssh" \
  | base64 \
  | ssh $SECONDARY 'umask 077; base64 -d > $GH_KEY_PATH && chmod 600 $GH_KEY_PATH'
```

Verify with `ssh-keygen -y -f $GH_KEY_PATH` on `$SECONDARY`; it should
print the public half. Then register the public half with the upstream:

```fish
op read "$GH_KEY_REF/public key"   # copy output to GitHub Settings → SSH Keys
```

### E. Configure `$SECONDARY`'s ssh client to use the new key for the upstream

Append to `$SECONDARY`'s `~/.ssh/config`:

```
Host github.com
  HostName github.com
  User git
  IdentityFile $GH_KEY_PATH
  IdentitiesOnly yes
```

`IdentitiesOnly yes` is required: without it, `$SECONDARY` will keep
trying any forwarded-agent keys first (and silently bypass the
per-machine key), defeating the design.

Do this transfer via stdin pipe, not printf-with-`\n`:

```fish
echo 'Host github.com
  HostName github.com
  User git
  IdentityFile $GH_KEY_PATH
  IdentitiesOnly yes' | ssh $SECONDARY 'cat >> ~/.ssh/config'
```

### F. Ensure `/etc/paths.d` on `$SECONDARY` includes Homebrew

Non-interactive ssh sessions on macOS use the system `/etc/paths` +
`/etc/paths.d/*` to assemble PATH, **not** any user-shell rc files. If
`$SECONDARY` is on Apple Silicon and lacks an `/etc/paths.d/homebrew`
entry, `op`, `brew`, and `mosh-server` will be unfindable in non-
interactive sessions. Mosh particularly cares: it tries to spawn
`mosh-server` over the SSH bootstrap and aborts if it can't find it.

```fish
# stage content (no sudo)
echo '/opt/homebrew/bin
/opt/homebrew/sbin' | ssh $SECONDARY 'cat > /tmp/homebrew-paths'

# install with sudo (separate session for TTY)
ssh -t $SECONDARY 'sudo install -m 644 -o root -g wheel /tmp/homebrew-paths /etc/paths.d/homebrew && rm /tmp/homebrew-paths'
```

`ssh -t` cannot share a TTY with a piped stdin, so the install step gets
its own SSH invocation. Two-shot.

## Trade-offs accepted

| Trade-off | Rationale |
|---|---|
| SA token in System.keychain is readable by any process the user runs | Same blast radius as S-51's login-keychain entry. The trust boundary is "this user account on this host," not "this Security Session." Fine for SA tokens that are already bearer-only secrets. |
| Sudo required to seed the SA token | One-time per machine. Acceptable cost vs. needing to maintain an agent process. |
| Per-machine SSH key means private key on disk on `$SECONDARY` | Required for headless operation. Compensating control: chmod 600, key scoped per-host (revoke one host without affecting others), key generated inside 1P (rotation path is straightforward). |
| Agent forwarding still allowed but no longer required | `$PRIMARY` may keep `ForwardAgent yes` as a safety net for the legacy path. Recommended posture is `no` once `$SECONDARY` is self-sufficient, but not enforced. |
| `op` cannot import existing keys | Generate fresh inside 1P. Migration cost is one-time per host pair. |
| Spec records the steps but does not codify them | `dotfiles secret push --backing-store=system` and a sibling `ssh-key push` would close the gap. Deferred until used a second time. |

## Test plan

Run from `$PRIMARY` against `$SECONDARY`. The `env -u SSH_AUTH_SOCK ssh
-a` prefix simulates the no-agent context that mosh sessions get. Pass
the iOS-equivalent test by passing this one.

| Test | Expected | Why this matters |
|---|---|---|
| `env -u SSH_AUTH_SOCK ssh -a $SECONDARY '/opt/homebrew/bin/op whoami'` | URL + Integration ID + `User Type: SERVICE_ACCOUNT` | SA token loads from System.keychain even with no GUI session and no forwarded agent. |
| `env -u SSH_AUTH_SOCK ssh -a $SECONDARY 'string length -- $OP_SERVICE_ACCOUNT_TOKEN'` | Non-zero (SA tokens are typically 800-900 chars) | `secrets.fish` is sourcing `secret-cache-read` and getting a populated value. |
| `env -u SSH_AUTH_SOCK ssh -a $SECONDARY 'ssh -T git@github.com 2>&1; ssh-add -l 2>&1'` | "Hi $USER!" + "Could not open a connection to your authentication agent." | Per-machine SSH key authenticates to upstream without any forwarded agent in play. |
| `ssh $SECONDARY '/opt/homebrew/bin/op whoami'` reports a different `Integration ID` than the same command from `$PRIMARY` | Per-machine SA isolation is real. | Compromise of one machine does not flow to the other. |
| `ssh $SECONDARY 'which mosh-server op brew'` | All three return paths under `/opt/homebrew/bin/` | Non-interactive PATH is consistent with interactive; mosh from `$iOS_CLIENT` will work. |

## Files changed

**Per-host machine state (not chezmoi-managed, not in this repo):**

- `$SECONDARY` System.keychain: new `OP_SERVICE_ACCOUNT_TOKEN` entry.
- `$SECONDARY` `$GH_KEY_PATH`: new private key (mode 600).
- `$SECONDARY` `~/.ssh/config`: appended Host-block for the upstream.
- `$SECONDARY` `/etc/paths.d/homebrew`: two-line file.
- 1Password vault: new SSH-key item for the per-machine key, plus per-
  host SA token.
- Upstream (e.g. github.com): new SSH key registration.

**Repo (chezmoi/docs):**

- `docs/specs/S-53-headless-mac-credential-pattern.md` (this spec).
- `docs/specs/S-51-multi-machine-sa-access.md`: banner pointing here.
- `docs/1password-multi-machine.md`: "Boot-time keychain lock" section
  cross-references this spec for the resolution.
- `docs/secrets-architecture.md`: S-51-errata callouts updated.
- `docs/operations/2026-05-mini-sa-seed.md`: status banner updated.
- `docs/tasks.md`: S-53 entry, S-51 follow-up note.
- `docs/sync-log.md`: hostname-tagged entry.

**Not changed:**

- `home/dot_config/fish/conf.d/secrets.fish`: untouched. Existing
  `secret-cache-read` already searches via the default keychain list,
  which on a non-GUI session resolves to System.keychain. No code
  change needed.
- `home/dot_local/bin/executable_secret-cache-read`: unchanged. Its
  cache-write path still targets the user's default keychain (login),
  which is fine — the System.keychain entry takes precedence on read
  because it's in the search list ahead of (or in lieu of) the locked
  login keychain.
- `home/dot_config/fish/functions/dotfiles.fish`: `secret push`
  unchanged. Codifying the System.keychain variant is future work.

## Non-goals

- Codifying the System.keychain seed into `dotfiles secret push`. Manual
  for now; revisit if applied to a third machine.
- A `dotfiles ssh-key push` helper. Same reason.
- Replacing forwarded-agent on `$PRIMARY`. The default stays `yes` as a
  safety net; users who want stricter isolation can flip to `no` per
  their threat model.
- Solving the cross-1P-account SA grant problem. Vaults and SAs must
  share a 1P account; that's a 1P platform constraint, not addressable
  here.
- Replacing the per-Security-Session unlock model. There is no public
  macOS API for that; the workaround is a backing store that doesn't
  need unlock.

## Future work

1. ~~**Codify in `dotfiles secret push`.** Add a `--backing-store=system`
   flag; have the helper sudo-tee into System.keychain instead of
   user-keychain. Acceptance: applying the same fix to a third host
   becomes one command.~~ **Done in [S-63](S-63-secret-rotate-multi-host.md):**
   `dotfiles secret push VAR target... --backing-store=system` handles
   seed + rotate + multi-host in one invocation, with delete-then-add
   semantics for System.keychain (the `-U` rotation gotcha is documented
   there as Decision 2).
2. **`dotfiles ssh-key push`.** Wraps the generate-in-1P → base64-pipe →
   register-with-upstream flow. Acceptance: bootstrapping a new
   `$SECONDARY` for git auth becomes one command.
3. **Reconsider login.keychain ACL.** A future macOS may expose Security
   Session bridging APIs. If that lands, login.keychain becomes a
   viable backing store again and System.keychain seeding can be
   reversed.
4. **Audit blast radius.** With SA tokens on multiple hosts, the per-host
   SA's vault grants compound. A periodic audit script that lists which
   SAs can read which vaults is worth building.

## Related specs

- [S-49](S-49-dual-mode-op-via-fish-interceptor.md) — token-loading
  mechanics on `$PRIMARY`. Unchanged by this spec.
- [S-51](S-51-multi-machine-sa-access.md) — the gate widening + remote
  Keychain seed. The "Operational prerequisite" gap there is closed by
  this spec.
- [S-46](S-46-three-vault-model-for-agent-infra-secrets.md) — vault
  scope tiering. Orthogonal; combine if you want both per-host SAs and
  scope-tiered vault grants.
- [S-52](S-52-secrets-architecture-synthesis-doc.md) — overall map.
  Should be regenerated to reflect this spec; deferred until next
  natural sweep.
