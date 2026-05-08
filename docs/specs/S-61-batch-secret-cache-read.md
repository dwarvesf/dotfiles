---
id: S-61
title: `secret-cache-read --batch` collapses N forks into one (~15 ms fish-startup win)
type: perf
status: done
date: 2026-05-09
supersedes_branch: perf/batch-secret-cache (originally drafted as S-55, renumbered to avoid collision with S-55-claude-md-modify-idempotency)
---

# S-61: `secret-cache-read --batch` collapses N forks into one

## Problem

`secrets.fish.tmpl` previously called `secret-cache-read VAR REF` once
per secret at every login fish startup. With 4 registered vars
(`OP_SERVICE_ACCOUNT_TOKEN`, `CLOUDFLARE_API_TOKEN`, `R2_ACCESS_KEY_ID`,
`R2_SECRET_ACCESS_KEY`), that is 4 separate bash subshell forks per
login. Each fork pays bash startup cost on top of the irreducible
~13 ms `security find-generic-password` syscall. On Hans Air M4 cold
fish startup, 4 forks measured ~170 ms attributed to this block.

Two evolutions on the cache-read script (post-branch creation):

1. `S-49` ratified dual-mode `op` (interceptor strips token only when
   interactive); the script does not depend on this.
2. `S-51` added `-A` to `security add-generic-password` so cross-
   Security-Session reads work for SSH-spawned shells. Already in main.
3. Negative-cache (24h TTL) for failed `op read` calls, dampening
   repeated startup tax on broken refs. Already in main.

This spec adds a `--batch` mode that collapses N pairs into one bash
invocation while preserving (1) SA-token-first ordering and (2) the
negative-cache + `-A` improvements that landed since the branch was
drafted.

## Solution

### `home/dot_local/bin/executable_secret-cache-read`

Refactor into a `_load_one` helper (Keychain hit -> negative-cache
check -> `op read` -> cache success or failure) plus two callers:

- **single-pair mode** (legacy, ad-hoc): `secret-cache-read VAR REF`
  echoes the resolved value, falling through to `_load_one`.
- **batch mode**: `secret-cache-read --batch VAR1 REF1 [VAR2 REF2 ...]`
  emits NUL-separated `VAR\0VALUE\0VAR\0VALUE\0...` to stdout. Inside
  the script, OP_SERVICE_ACCOUNT_TOKEN is resolved first (pass 1) and
  exported into the script's env so subsequent `_load_one` calls in
  pass 2 inherit bearer auth for any `op read` fallback.

`_load_one` keeps main's negative-cache (24h TTL) and `-A` flag for
cross-Security-Session reads, both unchanged from the pre-S-61 single-
pair path.

### `home/dot_config/fish/conf.d/secrets.fish.tmpl`

Replace the per-var `set -gx VAR ($_sc "VAR" "REF")` loop with a single
`secret-cache-read --batch VAR1 REF1 VAR2 REF2 ...` invocation, then
split the NUL-separated output and `set -gx` each pair in fish.

The `is-login` gate is preserved (S-51); the explicit "load
OP_SERVICE_ACCOUNT_TOKEN first" template-time conditional is removed
because the script handles ordering internally.

## Honest measurement

Originally predicted ~50 ms savings; actual is ~15 ms because the
expensive part is `security find-generic-password` itself (~13 ms × N,
kernel-side, irreducible). Batching only collapses bash-startup
amortization (~3 ms × N). 170 ms -> 155 ms on Hans Air M4 across 5
cold-fish runs. Net win is real but modest.

The bigger win is structural: the template no longer has a fragile
template-time conditional for "load this var before others"; ordering
is the script's responsibility, where it belongs.

## Test

1. **Render check.** `chezmoi execute-template <
   home/dot_config/fish/conf.d/secrets.fish.tmpl` produces a file
   containing exactly one invocation of `secret-cache-read --batch`,
   followed by the `for ... in (seq 1 2 ...)` split-and-export loop.
2. **Fish syntax.** `fish -n` clean on rendered output.
3. **Shellcheck.** `shellcheck --severity=warning
   home/dot_local/bin/executable_secret-cache-read` clean.
4. **Functional, single-pair.** `secret-cache-read OP_SERVICE_ACCOUNT_TOKEN
   op://Private/op-service-account-ops/credential` echoes the cached
   token (or empty on Keychain miss + op-read failure).
5. **Functional, batch.** `secret-cache-read --batch
   OP_SERVICE_ACCOUNT_TOKEN op://... CLOUDFLARE_API_TOKEN op://...`
   emits two NUL-separated `VAR\0VALUE` pairs to stdout. `string split0`
   in fish recovers them as a 4-element list.
6. **End-to-end.** `exec fish -l`; all 4 secrets are populated
   (`echo $OP_SERVICE_ACCOUNT_TOKEN | wc -c`, etc., return non-zero
   lengths). No 1Password popup on warm start.
7. **Negative-cache preserved.** Touch a fake bad ref into the
   `secrets.toml`, run `exec fish -l`, confirm
   `~/.cache/secret-cache-read/<VAR>.miss` exists; subsequent
   shell start does not re-call `op read`.
8. **Profile.** `for i in (seq 5); time fish -l -c exit; end` reports
   ~15 ms reduction vs the pre-S-61 baseline on Hans Air M4. Mac mini
   reports a similar reduction.

## Out of scope

- **Parallel `op read` calls** for cache misses. The kernel
  `security find-generic-password` is still the bottleneck; parallelism
  would only help once N >> 4 with mostly-cache-miss state, which is
  not the typical shell-startup case.
- **Removing the single-pair entry point.** Kept for ad-hoc
  invocations and back-compat with anything else calling the script.
- **NUL-separated alternatives** (e.g. JSON, env-file). NUL is the
  simplest and avoids escaping concerns for secrets containing
  whitespace, quotes, or the literal `=` character.

## Definition of done (per S-44)

- [x] Spec frontmatter `status: done`
- [x] Tick in `docs/tasks.md`
- [x] Hostname-tagged entry in `docs/sync-log.md`
- [x] Test 1, 2, 3 pass on Mac mini; test 6 verified end-to-end
