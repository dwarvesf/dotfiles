---
id: S-63
title: Multi-host secret upsert (extends `dotfiles secret push` for rotation + System.keychain backing)
type: feature
status: proposed
date: 2026-05-10
extends: S-51, S-53
---

# S-63: Multi-host secret upsert

Closes [S-53 § Future work item 1](S-53-headless-mac-credential-pattern.md#future-work) ("Codify in `dotfiles secret push`. Add a `--backing-store=system` flag.") and [S-51 § Trade-offs row 2](S-51-multi-machine-sa-access.md#trade-offs-accepted) ("Token rotation requires re-running `dotfiles secret push` per remote. Could be automated later if rotation becomes frequent."). Promotes `dotfiles secret push` from a single-host login-keychain seed into a multi-host upsert that handles both backing stores, both seed and rotate cases, and verifies each target before claiming success.

## Variables used in this spec

Same placeholder vocabulary as [S-51](S-51-multi-machine-sa-access.md#variables-used-in-this-spec) and [S-53](S-53-headless-mac-credential-pattern.md#variables-used-in-this-spec), augmented with one new placeholder.

| Placeholder | Meaning | Example |
|---|---|---|
| `$PRIMARY` | Daily-driver Mac with continuous GUI session, `op` biometric works. | A MacBook you carry. |
| `$SECONDARY[1..N]` | One or more headless or mostly-headless Macs, operated over SSH. | A Mac mini, a build host. |
| `$SA_REF` | `op://Vault/Item/credential` reference to the SA token (or any other registered secret). | `op://Agents/host-sa/credential` |
| `$VAR_NAME` | Registered secret name in `.chezmoidata/secrets.toml`. | `OP_SERVICE_ACCOUNT_TOKEN` |
| `$BACKING` (NEW) | One of `login` or `system`. Selects the keychain to write to on each target. | `system` |

## Problem

Three concrete pain points emerge once `dotfiles secret push` is in regular operational use:

### Pain 1: rotation requires a multi-step manual paste

Today's `push` is single-host and write-only with `-U`. That works for first-seed and for login-keychain rotations (per-user keychain has no GUI gate on ACL updates). It silently fails for **System.keychain rotations**, which is the canonical S-53 backing store for the SSH/mosh path:

| Backing store | Rotation via `add ... -U` | Why |
|---|---|---|
| login.keychain | Works | Per-user keychain; ACL update needs no GUI confirmation. |
| **System.keychain** | **Fails over non-TTY SSH**: `SecKeychainItemSetAccess: User interaction is not allowed` + `SecKeychainItemCreateFromContent: The specified item already exists in the keychain`. Exit code 0 but no value change. | macOS gates System.keychain ACL updates behind a GUI prompt that a piped SSH session can't satisfy. |

The correct rotation pattern for System.keychain is **delete-then-add**, not `add -U`. The current `push` doesn't know about this fork.

### Pain 2: one-host-per-invocation when N hosts share the same SA

A real rotation across `$PRIMARY` + N `$SECONDARY` hosts is N+1 invocations today. Each invocation re-prompts biometric on `$PRIMARY` (re-fetches the same value from 1Password) and re-paginates the verify output. Friction scales linearly with host count and each step has its own typo surface.

### Pain 3: stale negative-cache survives the seed

`secret-cache-read` writes a `$VAR.miss` marker into `~/.cache/secret-cache-read/` when `op read` fallback fails (24h TTL, S-61 design). After a seed/rotate, that marker is stale: the next login still skips the slow path for 24h, but the slow path would now succeed. The user-visible symptom is "I just rotated the SA but `$CLOUDFLARE_API_TOKEN` is still empty in fresh shells." Manual remediation is `rm ~/.cache/secret-cache-read/$VAR.miss` after every seed.

## Design

### Decision 1: extend `push`, do not introduce a new verb

`dotfiles secret push` already has the right English semantics ("make the value live on the target") and the right invariants (biometric-first read on `$PRIMARY`, pipe over SSH, never echo the value, verify by read-back). A new `rotate` verb would duplicate ~80% of the surface and force the caller to know whether they're seeding or rotating. The CLI shouldn't ask the human to make that distinction; the helper can detect it cheaply.

### Decision 2: upsert semantics by auto-detection

Per-target flow:

1. Probe: does `$VAR_NAME` exist on this target's chosen backing store?
2. If yes: delete first.
3. Add fresh.
4. Read back the prefix; refuse to claim success unless the prefix matches.

| Pre-state | Old behavior (`-U`) | New behavior (delete-then-add) |
|---|---|---|
| Entry absent | Add (works) | Add (works) |
| Entry present, login.keychain | Update via `-U` (works) | Delete + Add (works, slightly more I/O) |
| Entry present, System.keychain | `-U` fails over SSH (broken) | Delete + Add (works) |

Delete-then-add subsumes both cases at the cost of one extra keychain op per rotation. That cost is irrelevant compared to the network round-trip per target.

### Decision 3: variadic targets in one invocation

```fish
dotfiles secret push $VAR_NAME $TARGET... [--backing-store=login|system] [--local]
```

`$TARGET...` is one or more SSH aliases. `--local` adds the local machine to the iteration list (default off; opt-in to avoid surprise). Iteration is **sequential**, not parallel: parallel sudo prompts would interleave biometric/password UI in incomprehensible ways. Sequential keeps the prompt order deterministic and the failure isolation clean.

### Decision 4: `--backing-store` flag with conservative default

`--backing-store=login` (default) preserves S-51 backwards-compat: every existing `dotfiles secret push` invocation behaves identically post-S-63. `--backing-store=system` opts in to the S-53 path (`/Library/Keychains/System.keychain`, sudo wrapper, delete-then-add).

| Flag value | Target keychain | Sudo? | Rotation pattern |
|---|---|---|---|
| `login` (default) | `~/Library/Keychains/login.keychain-db` | No | Delete-then-add (still upsert, still works) |
| `system` | `/Library/Keychains/System.keychain` | Yes (passwordless on remote per ADR; password prompt on local) | Delete-then-add (mandatory) |

The default stays `login` because:

- Existing `dotfiles secret push CLOUDFLARE_API_TOKEN ...` invocations target user-scoped secrets, not the SA token, and login.keychain is the right home for those.
- Surprise migration from login → System on next-rotate would silently double-write (entries in both keychains until the user notices), which is messier than a noisy opt-in.

### Decision 5: sudo posture is a precondition, not a problem to solve

For `--backing-store=system`:

- **Local**: `sudo` will prompt for the user's password; the helper accepts that single prompt and proceeds.
- **Remote**: passwordless `sudo` for `security` (or full `(ALL) NOPASSWD: ALL`) is a precondition. The helper probes via `ssh $TARGET 'sudo -n true'` before piping the value; if sudo would prompt, the helper aborts with an actionable message instead of hanging.

Encoding the sudo grant into the helper (e.g. shipping a sudoers fragment) is out of scope; that's a host-provisioning concern, not a secret-handling one.

### Decision 6: post-seed neg-cache cleanup as a side-effect

After a successful per-target upsert, the helper unlinks `$XDG_CACHE_HOME/secret-cache-read/$VAR.miss` (resolving via `${XDG_CACHE_HOME:-$HOME/.cache}`) on that target. Best-effort, silent on failure (the file may not exist; that's the happy path). This closes Pain 3 inline so the user never has to remember.

### Decision 7: verify-by-readback unchanged

S-51's read-back-the-prefix verification stays the success contract. The helper compares the first 4 bytes of the read-back to the first 4 bytes of the value sent. Anything else (length mismatch, prefix mismatch, empty read-back) is a hard failure for that target. Other targets continue (per Decision 8).

### Decision 8: per-target failure isolation, summary at end

A failure on `$SECONDARY[k]` does not abort the iteration. The helper prints a per-target verdict line as it goes (`✓ $TARGET seeded` / `✗ $TARGET <reason>`) and emits a final summary: total attempted, succeeded, failed. Exit code is 0 if all succeeded, 1 if any failed. This matches operational reality: a transient SSH failure on one host shouldn't mean re-running for the others.

### Decision 9: never echo the value, never put it in argv

The helper inherits S-51's existing safe-form discipline:

- `op read` output goes directly into `ssh stdin` via pipe (never into a fish variable that could leak via `set -S`).
- Remote `security add-generic-password -w "$(cat)"` reads from stdin via subshell. Brief argv exposure (`ps -ef` window of milliseconds) is the same trade-off S-51 accepted.
- All `secret-guard` patterns from [S-62](S-62-secret-guard-pretooluse-hook.md) apply to the helper's source: any added test scripts must use the documented safe forms or carry the explicit bypass marker.

## Implementation steps

### A. Fish wrapper: extend `dotfiles secret push` arg parsing

In `home/dot_config/fish/functions/dotfiles.fish`, replace the existing `case push` block (lines 271-348 in the pre-S-63 source). New arg shape:

```fish
dotfiles secret push VAR_NAME TARGET [TARGET...] [--backing-store=login|system] [--local]
```

Parsing order: pull flags first (any position), then positional `VAR_NAME`, then 1+ targets. Validate:

- `VAR_NAME` is registered in `.chezmoidata/secrets.toml` (existing check).
- At least one of: `--local`, or 1+ `TARGET` entries.
- `--backing-store` value is `login` or `system` (default `login`).

Fail fast on invalid shapes; print a usage line that includes both backing-store options and the multi-target form.

### B. Local-side `op read` once

```fish
set -l val (env -u OP_SERVICE_ACCOUNT_TOKEN op read "$ref" 2>/dev/null)
```

Same as today. Read once into a fish-local variable that lives only inside the function (no global, no export). The value gets piped into each per-target write, never re-fetched.

### C. Per-target upsert helper (new bash script)

New file: `home/dot_local/bin/executable_secret-upsert-target`. Bash because the per-target dance needs careful sudo + ssh + heredoc handling that fish-quoting makes unreadable.

Signature:

```bash
secret-upsert-target VAR_NAME BACKING_STORE TARGET < value-on-stdin
```

`TARGET` is either `local` or an SSH alias. `BACKING_STORE` is `login` or `system`. Stdin carries the value (one read).

Pseudocode (real code in PR):

```bash
case "$BACKING_STORE" in
  login)  KCSPEC="";  SUDO="" ;;
  system) KCSPEC="/Library/Keychains/System.keychain"; SUDO="sudo" ;;
esac

# Build the remote-or-local command. Both paths read value from stdin.
DEL="$SUDO security delete-generic-password -a \"\$USER\" -s \"$VAR_NAME\" $KCSPEC 2>/dev/null || true"
ADD="$SUDO security add-generic-password -a \"\$USER\" -s \"$VAR_NAME\" -w \"\$(cat)\" -A -T /usr/bin/security -T /opt/homebrew/bin/op $KCSPEC"
VERIFY="$SUDO security find-generic-password -a \"\$USER\" -s \"$VAR_NAME\" -w $KCSPEC | head -c 4"
NEGCLEAR="rm -f \"\${XDG_CACHE_HOME:-\$HOME/.cache}/secret-cache-read/$VAR_NAME.miss\" 2>/dev/null || true"

if [ "$TARGET" = "local" ]; then
  # Probe sudo if system-store
  [ "$BACKING_STORE" = "system" ] && sudo -v
  bash -c "$DEL"; tee /dev/null | bash -c "$ADD"   # tee preserves stdin
  bash -c "$VERIFY"
  bash -c "$NEGCLEAR"
else
  # Probe SSH and sudo posture
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$TARGET" true || die "ssh unreachable"
  if [ "$BACKING_STORE" = "system" ]; then
    ssh "$TARGET" 'sudo -n true' 2>/dev/null || die "passwordless sudo not configured on $TARGET"
  fi
  ssh "$TARGET" "bash -c '$DEL'"
  ssh "$TARGET" "bash -c '$ADD'" < <(cat)   # stream stdin into the add
  prefix=$(ssh "$TARGET" "bash -c '$VERIFY'")
  ssh "$TARGET" "bash -c '$NEGCLEAR'"
fi
```

(The PR will use a single-pass stdin design rather than `tee`; the pseudocode is for illustration.)

### D. Iteration loop in fish wrapper

```fish
set -l targets   # collected from positional args
set -l backing login   # default
# (parse args into $targets and $backing)

# Read value once locally
set -l val (env -u OP_SERVICE_ACCOUNT_TOKEN op read "$ref" 2>/dev/null)
test -z "$val"; and echo "✗ op read $ref returned empty"; and return 1

set -l ok 0
set -l fail 0
for t in $targets
  if echo -n $val | secret-upsert-target $var $backing $t
    echo "✓ $t"
    set ok (math $ok + 1)
  else
    echo "✗ $t"
    set fail (math $fail + 1)
  end
end
echo "---"
echo "Summary: $ok succeeded, $fail failed (of "(count $targets)" targets)"
test $fail -eq 0
```

### E. Help text + usage examples

Update the in-function usage block to show all four shapes:

```
Usage: dotfiles secret push VAR_NAME TARGET [TARGET...] [--backing-store=login|system] [--local]

Examples:
  # Original S-51 single-host login-keychain seed (still works):
  dotfiles secret push CLOUDFLARE_API_TOKEN remote-host

  # S-53 System.keychain seed for one headless host:
  dotfiles secret push OP_SERVICE_ACCOUNT_TOKEN remote-host --backing-store=system

  # Multi-host rotation (the S-63 win):
  dotfiles secret push OP_SERVICE_ACCOUNT_TOKEN remote-host-1 remote-host-2 --backing-store=system

  # Local + remote in one shot (e.g. rotating across $PRIMARY + $SECONDARY):
  dotfiles secret push OP_SERVICE_ACCOUNT_TOKEN remote-host --local --backing-store=system
```

## Trade-offs accepted

| Trade-off | Rationale |
|---|---|
| Default `--backing-store` stays `login`, not `system` | Backwards-compat with S-51 invocations. Users opt into the S-53 path explicitly when they know they need it. Migration to system-default would silently double-write on next-rotate; bad UX. |
| Iteration is sequential, not parallel | Parallel sudo prompts and biometric flows interleave UI illegibly. Sequential is slower across 5+ hosts but readable. Revisit if rotation across 10+ hosts becomes routine. |
| Per-target failure does not abort iteration | A flaky network on one host shouldn't force re-running for all. Final summary + non-zero exit on any failure preserves CI-friendliness. |
| Sudo grant on remote is a precondition, not a feature | Provisioning is out of scope; the helper aborts with an actionable message instead of hanging on a sudo prompt. |
| One extra keychain op per rotation (delete + add vs. just `-U`) | Negligible cost. Subsumes the System.keychain rotation gotcha cleanly without a backing-store switch in the rotation path. |
| Brief argv exposure of the value via `-w "$(cat)"` | Same trade-off S-51 accepted. Eliminating it requires a different `security` CLI surface that doesn't exist. |
| `secret-upsert-target` is a separate bash script, not a fish function | Fish quoting + remote sudo + heredocs is unreadable past two layers. Bash gets the dance right. Mirrors `secret-cache-read` precedent. |
| Daemon-restart hook (e.g. `kickstart -k` after rotate) is out of scope | Each daemon's restart semantics are different; no clean general-purpose verb. Track as future work if a clear pattern emerges. |

## Test plan

Three layers, mirroring S-51's structure: doc verification, $PRIMARY-side regression, end-to-end on $SECONDARY.

### Doc verification (framework discipline)

Add S-63 to `FRAMEWORK_DOCS=` in `scripts/test-doc-discipline.sh`. Add the new bash helper too:

```bash
FRAMEWORK_DOCS=(
    ...existing...
    "docs/specs/S-63-secret-rotate-multi-host.md"   # NEW
    "home/dot_local/bin/executable_secret-upsert-target"   # NEW
)
```

Personal markers (specific hostnames, user@host pairs, real `op://` paths, real Integration IDs) MUST NOT appear in the spec or the helper. The author's specific 2026-05-10 rotation event lives in `docs/operations/2026-05-10-sa-rotation-air-mini.md` (a new operations cookbook added in this PR), where personal markers are required.

### $PRIMARY-side regression (fast, no remote calls)

```fish
# 1. Existing single-host login-keychain push still works (no flag, no regression).
dotfiles secret push CLOUDFLARE_API_TOKEN $SECONDARY_SSH_ALIAS
#    expect: "✓ $SECONDARY_SSH_ALIAS" + summary "1 succeeded, 0 failed"

# 2. Usage line lists all four shapes when called with no args.
dotfiles secret push 2>&1 | grep -cE "^Usage|--backing-store|--local"
#    expect: ≥ 3

# 3. Invalid backing-store rejected.
dotfiles secret push CLOUDFLARE_API_TOKEN $SECONDARY_SSH_ALIAS --backing-store=invalid 2>&1 | grep -i "invalid"
#    expect: matches

# 4. Unknown VAR rejected (existing check, regression).
dotfiles secret push NOT_A_REGISTERED_VAR $SECONDARY_SSH_ALIAS 2>&1 | grep "not registered"
#    expect: matches

# 5. No targets rejected.
dotfiles secret push CLOUDFLARE_API_TOKEN 2>&1 | grep -i "usage"
#    expect: matches
```

### End-to-end ($SECONDARY-side)

```fish
# 6. New System.keychain backing on a fresh entry (seed case).
dotfiles secret push $VAR_NAME $SECONDARY_SSH_ALIAS --backing-store=system
#    expect: "✓ $SECONDARY_SSH_ALIAS" + summary "1 succeeded, 0 failed"

ssh $SECONDARY_SSH_ALIAS 'sudo security find-generic-password -a "$USER" -s $VAR_NAME -w /Library/Keychains/System.keychain | head -c 4'
#    expect: matches the value's prefix

# 7. Re-run the same command (rotation case, value unchanged) succeeds idempotently.
dotfiles secret push $VAR_NAME $SECONDARY_SSH_ALIAS --backing-store=system
#    expect: "✓ $SECONDARY_SSH_ALIAS" + same prefix on re-read

# 8. Multi-host in one invocation.
dotfiles secret push $VAR_NAME $SECONDARY_SSH_ALIAS_A $SECONDARY_SSH_ALIAS_B --backing-store=system
#    expect: "✓ A" then "✓ B" + summary "2 succeeded, 0 failed"

# 9. Per-target failure isolation. Use a known-bad SSH alias mid-list.
dotfiles secret push $VAR_NAME $SECONDARY_SSH_ALIAS_A no-such-host $SECONDARY_SSH_ALIAS_B --backing-store=system
#    expect: "✓ A", "✗ no-such-host (ssh unreachable)", "✓ B"
#    summary "2 succeeded, 1 failed"; exit code 1

# 10. Sudo posture probe on remote without passwordless sudo.
#     (Run on a host that has interactive sudo only.)
dotfiles secret push $VAR_NAME $TIGHT_SUDO_HOST --backing-store=system
#    expect: "✗ $TIGHT_SUDO_HOST (passwordless sudo not configured)"
#    exit code 1, no value sent.

# 11. Negative-cache cleanup happens.
ssh $SECONDARY_SSH_ALIAS 'touch ${XDG_CACHE_HOME:-$HOME/.cache}/secret-cache-read/$VAR_NAME.miss'
dotfiles secret push $VAR_NAME $SECONDARY_SSH_ALIAS --backing-store=system
ssh $SECONDARY_SSH_ALIAS 'test ! -f ${XDG_CACHE_HOME:-$HOME/.cache}/secret-cache-read/$VAR_NAME.miss'
#    expect: file removed by the helper

# 12. Value never leaks. Inspect remote shell history + `ps` snapshot.
ssh $SECONDARY_SSH_ALIAS 'history 2>/dev/null | grep -c "$(echo -n $val | head -c 8)"'
#    expect: 0
ssh $SECONDARY_SSH_ALIAS 'ps -ef | grep -c "$(echo -n $val | head -c 8)"' &
#    (run during the push; expect 0 hits since value is in argv only briefly)
```

### Local target (`--local`)

```fish
# 13. --local seeds the current machine, prompting for sudo password if --backing-store=system.
dotfiles secret push $VAR_NAME --local --backing-store=system
#    expect: sudo prompt once, "✓ local" + summary "1 succeeded, 0 failed"

# 14. --local + remote targets together.
dotfiles secret push $VAR_NAME $SECONDARY_SSH_ALIAS --local --backing-store=system
#    expect: "✓ local", "✓ $SECONDARY_SSH_ALIAS", summary "2 succeeded, 0 failed"
```

## Files changed

**New:**

- `docs/specs/S-63-secret-rotate-multi-host.md` (this spec)
- `docs/operations/2026-05-10-sa-rotation-air-mini.md` (author's specific rotation event; the personal-context cookbook that proves S-63 works in real use)
- `home/dot_local/bin/executable_secret-upsert-target` (new bash helper)

**Modified:**

- `home/dot_config/fish/functions/dotfiles.fish`: replace `case push` block (lines 271-348). New surface: arg parsing for variadic targets + `--backing-store` + `--local`, calls `secret-upsert-target` per target, prints summary.
- `scripts/test-doc-discipline.sh`: add the new spec + new helper to `FRAMEWORK_DOCS=`.
- `docs/specs/S-53-headless-mac-credential-pattern.md`: add a banner pointing at S-63 as the canonical helper for future rotations. Update § Future work item 1 to "✓ Done in S-63."
- `docs/specs/S-51-multi-machine-sa-access.md`: update § Trade-offs row 2 to "Done in S-63." Update spec chain table to include S-63.
- `docs/secrets-architecture.md`: regenerate `dotfiles secret push` row to reflect new shape.
- `docs/tasks.md`: add S-63 row.
- `docs/sync-log.md`: hostname-tagged entry for the S-63 ship + the 2026-05-10 rotation it codifies.

**Not changed:**

- `home/dot_local/bin/executable_secret-cache-read`: unchanged. The reader doesn't need to know about delete-then-add; it only reads. Negative-cache cleanup is the writer's job, now handled by `secret-upsert-target`.
- `home/dot_config/fish/conf.d/secrets.fish.tmpl`: unchanged. Loader logic is orthogonal.
- `.chezmoidata/secrets.toml`: unchanged. Registration schema is unaffected.

## Non-goals

- **Daemon-restart hook**. Each daemon's restart semantics differ (`launchctl kickstart -k` for some, SIGHUP for others, full bootout/bootstrap for others). No clean general-purpose verb. Track as future work; flag in operations cookbooks per rotation event.
- **Parallel-host execution**. Sequential keeps prompt order deterministic. Revisit if N grows past ~5.
- **Dry-run mode (`--dry-run`)**. The verify-by-readback already gives strong post-hoc confirmation; a dry-run would mostly just print SSH commands. Add if a real need surfaces.
- **`--all` to push to every registered target**. Premature; the helper expects an explicit host list. Adding `--all` requires a target-registry concept (which `.chezmoidata/secrets.toml` doesn't have today).
- **Encoding sudo grants in the dotfiles**. Provisioning is host-substrate territory; out of scope for a secrets helper.
- **Negative-cache cleanup for unrelated VARs on the same host**. Helper only clears `$VAR_NAME.miss`. If `$VAR_NAME`'s rotation also invalidates a different secret's cache (rare), that's the operator's call.
- **Cross-account 1Password support**. SAs are single-account. Multi-account rotation is a separate concern.

## Future work

1. **Daemon-restart hook**, per Non-goals 1. If a pattern emerges (e.g. "all `foundation.d.*` daemons should `kickstart -k` after `OP_SERVICE_ACCOUNT_TOKEN` rotation"), add a `--restart=<launchd-pattern>` flag.
2. **Parallel iteration with serialized prompts**, per Non-goals 2. A semaphore around the value-bearing pipe (one at a time) but parallel SSH probes + verify reads could cut wall-clock by ~3x for N=5.
3. **Target registry**, to enable `--all`. Could live in `.chezmoidata/hosts.toml` or extend `secrets.toml` per-secret. Bigger surface; defer until the manual host list becomes painful.
4. **Negative-cache TTL override**, so a rotation can mark cache fresh-and-valid for a wider list of vars at once. Optional UX polish.
5. **Pre-rotation SA-validity check**: probe `op whoami` against the new SA before piping it anywhere. Catches "I rotated to the wrong vault" earlier in the loop. Cheap.

## Spec chain

| Spec | What | Status |
|---|---|---|
| [S-49](S-49-dual-mode-op-via-fish-interceptor.md) | Dual-mode `op` interceptor | done |
| [S-51](S-51-multi-machine-sa-access.md) | Multi-machine SA access (`secret push` v1) | done |
| [S-53](S-53-headless-mac-credential-pattern.md) | System.keychain backing + per-machine SSH key | done |
| [S-61](S-61-batch-secret-cache-read.md) | Batched secret-cache-read | done |
| [S-62](S-62-secret-guard-pretooluse-hook.md) | Secret-guard PreToolUse hook | done |
| **S-63** | **Multi-host upsert (this spec)** | **proposed** |
