---
id: S-58
title: Per-machine `Host github.com` block in dotfiles ssh config (S-53 ratify)
type: feature
status: done
date: 2026-05-08
---

# S-58: Per-machine `Host github.com` block in dotfiles ssh config

## Problem

S-53 added a per-machine recipe: generate a fresh `ed25519` SSH key
inside 1Password, write its private half to `~/.ssh/id_ed25519_github`,
register the public half with GitHub. The recipe also wrote a
`Host github.com` block into `~/.ssh/config` so git SSH used the
per-machine key explicitly.

That config-file change was made **directly on the machine, not in the
dotfiles source**. When today's broad `chezmoi apply` ran during the
S-54 sync batch, the source's `dot_ssh/config.tmpl` (which has no
github block) overwrote the live file. The github block was clobbered.

Net result: github SSH falls through to the global `Host *
IdentityAgent` (1Password agent socket). It works if the agent has the
GitHub key enrolled, but it's not the per-machine path S-53 designed,
and the user's verbal preference (asked 2026-05-08 22:50) is to ratify
the block as cross-machine.

## Solution

Add a `Host github.com` block to `home/dot_ssh/config.tmpl`, **template-
conditional on the key file existing on the target machine**. Use
chezmoi's `stat` template function:

```diff
 {{ if .use_1password -}}
 # 1Password SSH Agent
 Host *
   IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
 {{- end }}
+
+{{- if stat (joinPath .chezmoi.homeDir ".ssh/id_ed25519_github") }}
+# Per-machine GitHub key (S-53 recipe creates the key inside 1Password,
+# pipes the private half to ~/.ssh/id_ed25519_github). The block deploys
+# only when the key is present, so fresh machines without S-53 done
+# don't break github SSH (block absent → 1P agent fallback works).
+Host github.com
+  HostName github.com
+  User git
+  IdentityFile ~/.ssh/id_ed25519_github
+  IdentitiesOnly yes
+{{- end }}
+
 # OrbStack Linux VMs
 Include ~/.orbstack/ssh/config
```

### Why conditional, not unconditional

Unconditional emission would have the block reference a missing file on
fresh machines. Combined with the global `Host *  IdentitiesOnly yes`,
that means github SSH sees no usable identity and fails. The block must
be opt-in. Conditioning on file existence is opt-in-via-S-53-ran:
running S-53 produces the key, the next `chezmoi apply` deploys the
block, github SSH works.

The alternative (chezmoi-data flag set during `chezmoi init`) would
require explicit user action on each machine. The file-existence trigger
is implicit and self-documenting.

## Test

1. **Source has the block.** `grep -A 5 'Host github.com'
   home/dot_ssh/config.tmpl` returns the 4-line block.
2. **Conditional renders correctly when key exists.** On Mac mini
   (key file present), `chezmoi cat ~/.ssh/config | grep -A 5
   'Host github.com'` returns the block.
3. **Conditional skips when key missing.** Move the key aside
   (`mv ~/.ssh/id_ed25519_github /tmp/`), `chezmoi cat ~/.ssh/config`
   produces a config with NO github block. Restore the key.
4. **Apply round-trip.** `chezmoi apply ~/.ssh/config`; the live file
   contains the block. Run again: idempotent.
5. **Functional: git push works.** `ssh -T git@github.com` returns
   "Hi <user>! You've successfully authenticated".

## Out of scope

- **Different identity file path per machine.** S-53 standardizes on
  `~/.ssh/id_ed25519_github`. If a future machine wants a different
  filename, that machine extends via `~/.ssh/config.d/<host>.local`
  (gitignored).
- **Templating the GitHub username.** Keep `User git` — that's the
  GitHub-specific SSH user, not the human user.
- **Replacing the global `Host *  IdentityAgent`.** The 1P agent block
  stays for non-github hosts that use 1P-stored keys.
- **Auto-running S-53 on fresh machines.** S-53 is interactive and
  involves browser confirmations; not worth automating into the apply
  path.

## Definition of done (per S-44)

- [x] Spec frontmatter `status: done`
- [x] Tick in `docs/tasks.md`
- [x] Hostname-tagged entry in `docs/sync-log.md`
- [x] Mac mini live `~/.ssh/config` contains the github block; second
      apply is idempotent; `ssh -T git@github.com` authenticates
