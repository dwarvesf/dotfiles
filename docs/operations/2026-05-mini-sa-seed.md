# 2026-05 mini SA token seed (S-51 rollout)

> **Status (2026-05-08): superseded for the SSH/mosh path.** Steps 1-4
> seed the SA token into the user's login Keychain successfully, but
> [S-51 errata 2026-05-07](../specs/S-51-multi-machine-sa-access.md#errata-2026-05-07)
> showed that login.keychain is unreachable from SSH/mosh sessions due to
> per-Security-Session unlock state. Step 5 (the cross-machine smoke test)
> and Step 6 (auto-login as mitigation) do not work.
> **[S-53](../specs/S-53-headless-mac-credential-pattern.md) is the
> canonical pattern**: System.keychain backing store for the SA token plus
> a per-machine SSH key for outbound `git`. Apply S-53 instead of this
> runbook for any new headless Mac. This file is preserved for historical
> context; do not extend it.

Operations runbook to seed `OP_SERVICE_ACCOUNT_TOKEN` into the Mac Mini's
login Keychain and bring [S-51](../specs/S-51-multi-machine-sa-access.md)
online end-to-end.

This is a **self-contained recipe**. Hand it to an agent (Claude, etc.)
running on `tieubao@mini` and it should be able to execute without further
context. The agent must be sitting in a session that can biometric-prompt
the user (i.e. invoked from the Mini's GUI Terminal, not over SSH key auth
from another machine).

## Pre-conditions (verify before starting)

1. You are logged in as `tieubao` at the Mini's GUI (`who` shows a `console` row).
2. You can see this runbook from the dotfiles working tree (currently on PR branch `feat/multi-machine-op`; once merged to main, this section's pre-deploy step becomes a plain `dotfiles update`).
3. 1Password desktop is running and signed in. `op account list` returns at least one account.
4. The repo at `~/workspace/tieubao/dotfiles` exists and is on a normal branch (most likely `main`, possibly behind origin).

If any of those is false, stop and surface the gap. Do not improvise around it.

## Step 1 — Pull the S-51 changes into the working tree

The PR (#76) may or may not be merged at the time you run this. Handle both:

```fish
cd ~/workspace/tieubao/dotfiles

# Fast-forward main if possible (no-op if already up to date).
git fetch origin

# If S-51 is already in main, just sync.
if git log origin/main --oneline | grep -q "S-51 multi-machine SA access"
    git checkout main
    git pull --ff-only
    chezmoi apply
else
    # PR still open. Cherry-pick the three files we need without switching branches.
    git checkout origin/feat/multi-machine-op -- \
        home/dot_config/fish/conf.d/secrets.fish.tmpl \
        home/dot_local/bin/executable_secret-cache-read \
        home/dot_config/fish/functions/dotfiles.fish

    chezmoi apply ~/.config/fish/conf.d/secrets.fish \
                  ~/.local/bin/secret-cache-read \
                  ~/.config/fish/functions/dotfiles.fish
end
```

After Step 1, `grep "^if status" ~/.config/fish/conf.d/secrets.fish` should print `if status is-login` (the new S-51 gate).

## Step 2 — Delete any prior narrow-ACL Keychain entry

If a previous attempt seeded the entry without `-A`, it has an ACL that
prevents SSH-context reads. Delete it before re-seeding so the new entry's
`-A` ACL takes effect cleanly. Idempotent: silently no-ops if no entry exists.

```fish
security delete-generic-password -a "$USER" -s OP_SERVICE_ACCOUNT_TOKEN 2>/dev/null
```

## Step 3 — Seed the SA token (one biometric popup expected)

```fish
env -u OP_SERVICE_ACCOUNT_TOKEN op read 'op://Private/op-service-account-ops/credential' \
  | bash -c 'security add-generic-password -a "$USER" -s OP_SERVICE_ACCOUNT_TOKEN -w "$(cat)" -A -U' \
  && echo "✓ seeded with -A"
```

Notes:
- `env -u OP_SERVICE_ACCOUNT_TOKEN` strips the bearer token from the `op read` env so it falls through to the user's biometric session. Required because the SA cannot read its own credential (S-46 keeps `Private` outside SA scope).
- `-A` makes the Keychain entry readable from any process the user owns, including SSH-originated processes. Same blast radius as the env-var model.
- Touch ID will prompt **on the Mini's screen** for the `op read`. The agent cannot dismiss it; the user does.

## Step 4 — Verify locally (no popup expected)

```fish
echo "=== entry exists and is readable from this context ==="
security find-generic-password -a "$USER" -s OP_SERVICE_ACCOUNT_TOKEN -w | head -c 4
# expect: ops_

echo "=== fish login loads it into env (the S-51 gate working) ==="
fish -l -c 'string sub -l 4 -- "$OP_SERVICE_ACCOUNT_TOKEN"'
# expect: ops_

echo "=== subprocess op uses bearer auth, no biometric ==="
fish -l -c 'bash -c "op whoami | grep \"User Type:\""'
# expect: User Type:  SERVICE_ACCOUNT
```

If any of those returns empty / wrong, stop and surface what was returned.
Do not retry blindly.

## Step 5 — Tell the human to run the cross-machine smoke test

Once Steps 1-4 pass, the human (back at their other machine) should run:

```fish
ssh mini-tieubao -- /opt/homebrew/bin/fish -l -c 'bash -c "op whoami | grep \"User Type:\""'
# expect: User Type:  SERVICE_ACCOUNT  with NO popup on the Mini's screen
```

If that prints `SERVICE_ACCOUNT` with no popup, S-51 is fully validated
end-to-end and PR #76 is safe to merge.

## Step 6 — Optional: persist the unlock across reboots

> **Note (2026-05-07):** Empirical testing showed that auto-login does
> **not** make the SA cache readable from SSH/mosh sessions even when the
> Mini's GUI is logged in continuously. macOS holds keychain unlock state
> per Security Session, not per user; SSH and mosh sessions create their
> own Security Session distinct from the console GUI session, and that
> session's view of the login keychain is locked. The "if you skip this,
> log into the GUI" guidance below is therefore **not** sufficient to
> deliver no-popup SSH access. See
> [S-51 errata 2026-05-07](../specs/S-51-multi-machine-sa-access.md#errata-2026-05-07).
> The Step-6 guidance below is preserved for historical accuracy.

The seeded entry survives reboots, but the login keychain locks at boot
until something unlocks it. SSH key auth doesn't unlock it; only a GUI
login (or auto-login) does.

For a personal home Mini that's used as a daily driver, enable auto-login:

> System Settings → Users & Groups → Auto-login → set to `tieubao`.

Trade-off: anyone who power-cycles the Mini gets your GUI session. Acceptable
for a home Mini behind a locked door.

If you skip this, you'll need to physically log into the Mini's GUI (or be
present after every reboot) for the SA cache to remain usable from SSH.

This step is **operational, not codified in dotfiles**. Skip if you prefer
manual unlock.

## Cleanup if Step 1 used the cherry-pick branch

If Step 1 used the `git checkout origin/feat/multi-machine-op -- ...` path
(PR not merged yet), the working tree has files from a different branch.
After PR #76 merges to main, restore main as the source of truth:

```fish
cd ~/workspace/tieubao/dotfiles
git fetch origin
git checkout main
git pull --ff-only
chezmoi apply
```

After that, `git diff` against `origin/main` should be empty.

## Rollback

If anything goes sideways and you want to revert:

```fish
# Remove the Keychain entry
security delete-generic-password -a "$USER" -s OP_SERVICE_ACCOUNT_TOKEN

# Discard the cherry-picked files (only if Step 1 used the branch path)
cd ~/workspace/tieubao/dotfiles
git checkout HEAD -- home/dot_config/fish/conf.d/secrets.fish.tmpl \
                     home/dot_local/bin/executable_secret-cache-read \
                     home/dot_config/fish/functions/dotfiles.fish

chezmoi apply ~/.config/fish/conf.d/secrets.fish \
              ~/.local/bin/secret-cache-read \
              ~/.config/fish/functions/dotfiles.fish
```

## Spec / context

- Spec: [`../specs/S-51-multi-machine-sa-access.md`](../specs/S-51-multi-machine-sa-access.md)
- Architecture: [`../1password-multi-machine.md`](../1password-multi-machine.md)
- PR: https://github.com/dwarvesf/dotfiles/pull/76
