---
id: S-54
title: Load OP_SERVICE_ACCOUNT_TOKEN first in secrets.fish to suppress remote-shell 1P popups
type: fix
status: done
date: 2026-05-08
extends: S-53
---

# S-54: Load SA token first to suppress remote-shell 1P popups

## Problem

After [S-51](S-51-multi-machine-sa-access.md) widened `secrets.fish`'s gate
to `is-login`, every mosh / non-interactive SSH session on a `$SECONDARY`
host runs the secret-loading block. After [S-53](S-53-headless-mac-credential-pattern.md)
seeded `OP_SERVICE_ACCOUNT_TOKEN` into `$SECONDARY`'s System.keychain, that
specific var hits cache silently — but the *other* registered vars
(`CLOUDFLARE_API_TOKEN`, `R2_*`, etc.) are not seeded there and miss the
cache.

`secrets.fish.tmpl` iterates `.secrets` with Go's `range`, which sorts map
keys alphabetically. So on a fresh remote shell:

```
1. CLOUDFLARE_API_TOKEN     ← cache MISS, op read runs with NO bearer auth in env → 1P Desktop integration → POPUP
2. OP_SERVICE_ACCOUNT_TOKEN ← System.keychain hit, silent (now in env)
3. R2_ACCESS_KEY_ID         ← cache miss, op read with SA bearer → headless, no popup
4. R2_SECRET_ACCESS_KEY     ← same as 3
```

On step 1, `op` connects to 1P Desktop's integration helper. 1P walks the
peer-PID parent chain looking for a non-shell, non-system binary to attribute
the request to. On a Mac running Tailscale SSH, the chain is
`launchd → tailscaled → /usr/bin/login → fish → bash → op`. Shells / `login`
get skipped; **`tailscaled` is the first "interesting" ancestor**, so 1P
prompts `"Allow tailscaled to access 1Password?"` every fresh mosh session.

The popup is a misattribution: tailscaled isn't actually requesting anything.
The mechanical cause is the load order.

## Design

Bring `OP_SERVICE_ACCOUNT_TOKEN` to the head of the loader, before iterating
the rest of `.secrets`. Skip it inside the iteration to avoid double-loading.

```handlebars
{{- if hasKey .secrets "OP_SERVICE_ACCOUNT_TOKEN" }}
    set -gx OP_SERVICE_ACCOUNT_TOKEN ($_sc "OP_SERVICE_ACCOUNT_TOKEN" "{{ index .secrets "OP_SERVICE_ACCOUNT_TOKEN" }}")
{{- end }}
{{- range $var, $ref := .secrets }}
{{- if ne $var "OP_SERVICE_ACCOUNT_TOKEN" }}
    set -gx {{ $var }} ($_sc "{{ $var }}" "{{ $ref }}")
{{- end }}
{{- end }}
```

After this change, any subsequent cache miss falls through to `op read` with
`OP_SERVICE_ACCOUNT_TOKEN` already in env. `op` then uses bearer auth and
hits the 1P API directly — no Desktop integration call, no app-attribution
walk, no popup.

## Trade-offs accepted

| Trade-off | Rationale |
|---|---|
| Reorder is hard-coded in template (not data-driven) | `OP_SERVICE_ACCOUNT_TOKEN` is the only secret whose presence affects how *other* secrets load. Special-casing it in the template is simpler than introducing a "load priority" field in `.chezmoidata/secrets.toml`. Revisit if a second priority case appears. |
| If SA token isn't registered, behavior is unchanged | The `hasKey` guard makes the block emit only when the SA var is registered. Hosts that don't use SA tokens see the original alphabetical-only loop. |
| If SA token is registered but unresolvable (Keychain miss + `op read` failure), later vars still fall through to Desktop integration | Same failure mode as before this fix. The fix narrows the popup window from "every cold remote shell" to "every cold remote shell where SA token resolution itself failed." |
| Comment in the template references S-54 by ID | Keeps the *why* discoverable inline. Future readers tempted to "clean up" the special case will find this spec. |

## Test plan

```fish
# Render and confirm SA token comes first
chezmoi execute-template < home/dot_config/fish/conf.d/secrets.fish.tmpl \
  | grep -E "set -gx (OP_SERVICE_ACCOUNT_TOKEN|CLOUDFLARE)" \
  | head -2
# Expected: OP_SERVICE_ACCOUNT_TOKEN line first.

# Fish syntax check
chezmoi execute-template < home/dot_config/fish/conf.d/secrets.fish.tmpl | fish -n /dev/stdin
# Expected: clean exit.

# On $SECONDARY (post-apply), simulate a cold mosh session
ssh mini-tieubao 'fish -l -c "echo OP=$OP_SERVICE_ACCOUNT_TOKEN | string length; echo CF=$CLOUDFLARE_API_TOKEN | string length"'
# Expected: both report non-zero lengths, no 1P popup observed on Mini console.
```

## Files changed

- `home/dot_config/fish/conf.d/secrets.fish.tmpl`: emit `OP_SERVICE_ACCOUNT_TOKEN` line ahead of the iteration; skip it inside the loop.
- `docs/specs/S-54-load-sa-token-first.md`: this spec.
- `docs/tasks.md`: tick S-54.
- `docs/sync-log.md`: hostname-tagged entry.

## Non-goals

- Codifying `OP_SERVICE_ACCOUNT_TOKEN` into System.keychain seeding from the
  dotfiles repo. Still manual per S-53.
- Changing 1P's app-attribution behavior. The misattribution to `tailscaled`
  is a 1P implementation detail; we sidestep it rather than fight it.
- Suppressing the "tailscaled" entry already in 1P Desktop's app-authorization
  list. After this fix, the entry is dead; user can leave it or revoke it
  manually.

## Related specs

- [S-49](S-49-dual-mode-op-via-fish-interceptor.md) — established that
  `OP_SERVICE_ACCOUNT_TOKEN` is auto-loaded so subprocesses inherit bearer
  auth. This fix completes that contract for *intra-loader* subprocesses
  (the `secret-cache-read` bash subshells called by `secrets.fish` itself).
- [S-51](S-51-multi-machine-sa-access.md) — widened the gate so remote
  shells now run `secrets.fish`. Surfaced the load-order issue.
- [S-53](S-53-headless-mac-credential-pattern.md) — System.keychain seeding
  closed the SA-token-resolution gap on `$SECONDARY`. Left the *other*
  secrets miss-then-popup behavior, which this spec addresses.
