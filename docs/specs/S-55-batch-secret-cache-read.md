---
id: S-55
title: Batch mode for secret-cache-read to amortize bash-startup at fish login
type: perf
status: done
date: 2026-05-08
extends: S-49
---

# S-55: Batch mode for `secret-cache-read`

## Problem

`secrets.fish.tmpl` invokes `secret-cache-read` once per registered secret.
On the Air with N=4 secrets, this is 4 separate bash subprocess forks at
fish login time. Each `security find-generic-password` call inside takes
~13–14 ms (irreducible kernel-side cost), and bash startup adds ~3–5 ms
per fork. Combined cost: ~70 ms of fish startup.

Profile (`fish --profile-startup`, warm run, Hans-Air-M4):

```
17650 us  $_sc "CLOUDFLARE_API_TOKEN" ...
17458 us  $_sc "OP_SERVICE_ACCOUNT_TOKEN" ...
17354 us  $_sc "R2_ACCESS_KEY_ID" ...
17225 us  $_sc "R2_SECRET_ACCESS_KEY" ...
─────
~70 ms total in the secret pipeline (40% of 177 ms total fish startup)
```

The 4× bash-startup overhead is amortizable; the keychain-call overhead
is not.

## Design

Add `--batch` mode to `secret-cache-read`. Single bash invocation, takes
N pairs of `VAR REF`, emits NUL-separated `VAR\0VALUE\0VAR\0VALUE\0...`
on stdout.

```bash
secret-cache-read --batch \
  CLOUDFLARE_API_TOKEN  op://Private/Cloudflare API Token/credential \
  OP_SERVICE_ACCOUNT_TOKEN op://Private/op-service-account-trading/credential \
  R2_ACCESS_KEY_ID      op://Private/Cloudflare R2/username \
  R2_SECRET_ACCESS_KEY  op://Private/Cloudflare R2/credential
```

Fish-side caller uses `string split0` and a small `for`-loop to apply
each `set -gx`:

```fish
set -l _pairs ($HOME/.local/bin/secret-cache-read --batch ... | string split0)
for _i in (seq 1 2 (count $_pairs))
    set -gx $_pairs[$_i] $_pairs[(math $_i + 1)]
end
```

NUL-separated output sidesteps fish-string escaping issues entirely
(secret values cannot contain `\0`, so split is unambiguous).

### S-54 ordering preserved internally

The batch script still resolves `OP_SERVICE_ACCOUNT_TOKEN` first, before
iterating remaining vars. After it succeeds, the script `export`s the
token into its own bash environment so subsequent `_load_one` calls'
`op read` invocations see bearer auth. No change in observable behaviour
versus S-54's per-call ordering — the contract is just enforced inside
one process instead of across four.

### Single-pair mode preserved

The legacy `secret-cache-read VAR REF` form still works for ad-hoc
manual use and any other caller. Batch mode is opt-in via the leading
`--batch` token.

## Trade-offs accepted

| Trade-off | Rationale |
|---|---|
| Smaller win than initially estimated (~15 ms vs predicted ~50 ms) | The expensive part is `security find-generic-password` itself (~13 ms × 4 = ~52 ms irreducible), not bash startup. Batching only collapses the bash-overhead chunk. The savings is real but headline-modest. |
| New script API surface (`--batch`) | Cost of one extra `if` branch and a few helper-function refactors. Single-pair mode unchanged for back-compat. |
| NUL-separated output is bash/fish-specific | Won't work cleanly in zsh-only callers, but no zsh callers exist; `secret-cache-read` is fish-pipeline-only. If we add zsh later, switch to `\n`-separated with explicit value escaping. |
| Sparse-array unset trick (`unset 'vars[i]'`) | Works in bash 4+; required to avoid double-processing OP_SERVICE_ACCOUNT_TOKEN in pass 2. Documented inline. |

## Test plan

```fish
# Render and confirm batch invocation in output
chezmoi execute-template < home/dot_config/fish/conf.d/secrets.fish.tmpl \
  | grep -E "secret-cache-read --batch"
# Expected: one line with all VAR REF pairs joined.

# Fish syntax
chezmoi execute-template < home/dot_config/fish/conf.d/secrets.fish.tmpl | fish -n /dev/stdin

# Shellcheck
shellcheck --severity=warning home/dot_local/bin/executable_secret-cache-read

# Smoke: all four vars populated in fresh fish login (NEVER echo values)
fish -l -c '
echo OP=(string length -- $OP_SERVICE_ACCOUNT_TOKEN)
echo CF=(string length -- $CLOUDFLARE_API_TOKEN)
echo R2K=(string length -- $R2_ACCESS_KEY_ID)
echo R2S=(string length -- $R2_SECRET_ACCESS_KEY)
'
# Expected: four non-zero lengths, no popup.

# Profile delta (warm steady-state)
fish --profile-startup /tmp/before.log -lic exit  # checkout main, apply, run
fish --profile-startup /tmp/after.log  -lic exit  # checkout this branch, apply, run
diff <(awk '{sum+=$1} END {print sum}' /tmp/before.log) \
     <(awk '{sum+=$1} END {print sum}' /tmp/after.log)
# Expected delta on Hans-Air-M4: ~15 ms reduction.
```

## Files changed

- `home/dot_local/bin/executable_secret-cache-read`: add `--batch` mode +
  `_load_one` helper. Single-pair entry path preserved at the bottom.
- `home/dot_config/fish/conf.d/secrets.fish.tmpl`: replace per-secret
  `set -gx VAR ($_sc ...)` lines with one batched call + split-and-set
  loop. Comment block points to this spec.
- `docs/specs/S-55-batch-secret-cache-read.md`: this spec.
- `docs/tasks.md`: tick S-55.
- `docs/sync-log.md`: hostname-tagged entry.

## Non-goals

- Reducing `security find-generic-password` per-call cost. That's a
  macOS framework cost; nothing in this repo can change it.
- Caching resolved values across fish startups (e.g. /tmp/secret-cache).
  Adds an attack surface (plaintext file) for marginal additional gain.
  Keychain is the cache.
- Optimizing `mise hook-env` running twice on startup. Out of scope;
  upstream design choice.
- Optimizing `brew shellenv` (~15 ms). Replacing with hardcoded
  `fish_user_paths` would save it but couples to a brew prefix; punt.
- Mini-side perf wins. The popup-fix path (S-54) and the broader Mini
  remediation are separate; this spec is about steady-state cache-hit
  startup latency.

## Future work

1. **Profile budget.** Add an annual sanity check that fish startup
   stays under a target (e.g. 200 ms warm on Apple Silicon). If a
   future change blows past it, surface in `/dotfiles-sync`.
2. **Per-host secret subset.** Currently every host loads every var in
   `secrets.toml`. A future spec could let machines opt out of vars
   they don't need (the Mini doesn't need CLOUDFLARE/R2). Would
   compound with this fix and cut more time.

## Related specs

- [S-49](S-49-dual-mode-op-via-fish-interceptor.md) — established
  `secret-cache-read` as the lazy-resolution helper. This spec
  optimizes its invocation pattern.
- [S-54](S-54-load-sa-token-first.md) — ordering rule (SA token first).
  S-55 enforces the same rule inside a single process via a two-pass
  loop instead of relying on caller-side ordering.
