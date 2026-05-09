# Secret-handling cheatsheet (S-62 secret-guard hook)

Canonical patterns for using a 1Password secret in a Bash command
without leaking its value into the Claude Code session transcript.

The `secret-guard` hook (`~/.claude/hooks/secret-guard/secret-guard.sh`)
blocks any tool call that would put a resolved secret into the JSONL
transcript. This file lists the patterns that work AROUND the block,
so Claude can authenticate API calls and run authed CLIs without
either leaking or reaching for the bypass marker.

---

## TL;DR

| Use case | Recipe | Pattern |
|---|---|---|
| Bearer-token API call, secret already in env (CLOUDFLARE_API_TOKEN, OP_SERVICE_ACCOUNT_TOKEN, R2_*) | `curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" url` | P1 |
| Bearer-token API call, secret NOT pre-loaded | `TOKEN=$(op read 'op://...'); curl -H "Authorization: Bearer $TOKEN" url` | P2 |
| CLI that reads from env var | `TOKEN=$(op read 'op://...') my-cli ...` | P4 |
| CLI that reads auth from stdin (`-H @-`) | `cmd <<<"$(op read 'op://...')"` or `cmd @<(op read 'op://...')` | P6 |
| CLI that needs an auth file on disk | `op read 'op://...' > /tmp/auth && cmd /tmp/auth; rm /tmp/auth` | P7 |
| Put secret on clipboard for human | `op read 'op://...' \| pbcopy` | P8 |

If the auto-loaded env vars fit your need, use P1. It's the simplest.

---

## Pre-loaded environment

Fish startup auto-resolves the four registered secrets via
`secret-cache-read --batch` (see `~/.config/fish/conf.d/secrets.fish`,
S-49 / S-61). They are in Claude's Bash subshell environment from
session start:

| Var | 1Password ref |
|---|---|
| `CLOUDFLARE_API_TOKEN` | `op://Toolkit/cf-api-token/credential` |
| `R2_ACCESS_KEY_ID` | `op://Toolkit/cf-r2/username` |
| `R2_SECRET_ACCESS_KEY` | `op://Toolkit/cf-r2/credential` |
| `OP_SERVICE_ACCOUNT_TOKEN` | `op://Private/op-service-account-ops/credential` |

For these, **always prefer P1**.

To register more vars: `dotfiles secret add VAR_NAME 'op://Vault/Item/field'`,
re-source fish, the var becomes available in new Claude sessions.

---

## Patterns in detail

### P1 -- already-loaded env var pass-through

```bash
curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" https://api.example.com
aws s3 ls --profile default                  # uses $AWS_*
gh repo view --json description               # uses $GH_TOKEN
```

The literal `$VAR` in the command is a reference; bash expands it at
exec time. Transcript stores `$VAR`, not the value. Hook does not
match because no `op read`, no `echo`/`printf` of the var, no env
dump.

### P2 -- capture-then-use, single Bash call

```bash
TOKEN=$(op read 'op://Vault/Item/credential')
curl -H "Authorization: Bearer $TOKEN" https://api.example.com
```

Both statements run in the same `bash -c` invocation, so `$TOKEN`
is in scope for the second one. The `$()` capture covers the
`op read`. Use `;`, `&&`, or newlines to separate.

### P3 -- two separate Bash tool calls (DOES NOT WORK)

Each Bash tool call spawns a fresh shell; env vars do not persist
across tool calls. If you split capture and use across two calls,
the second call sees an empty `$TOKEN`. Use P2 (single call) instead.

### P4 -- env-prefix exec

```bash
TOKEN=$(op read 'op://Vault/Item/credential') my-app --use-env
```

Bash's `VAR=val cmd` syntax sets `VAR` only in `cmd`'s environment.
Use when the consumer reads its credential from env on its own.

### P5 -- bash -c subshell with token in env

```bash
TOKEN=$(op read 'op://Vault/Item/credential') bash -c 'curl -H "Authorization: Bearer $TOKEN" https://api.example.com'
```

For complex compositions where env-var-from-shell + interpolated
command-string is cleanest. Outer `$()` captures the read; inner
`$TOKEN` expands inside the subshell.

### P6 -- process substitution into stdin

```bash
curl -H @<(op read 'op://Vault/Item/auth-header') https://api.example.com
```

`<(...)` is process substitution: the inner command's stdout is
connected to a `/dev/fd/N` path which the outer command opens and
reads. The inner stdout never reaches the terminal. Useful when the
consumer wants `@filename` syntax for headers/auth and you don't
want a `/tmp` file.

### P7 -- file-based handoff with cleanup

```bash
op read 'op://Vault/Item/credential' > /tmp/auth.tmp \
    && cmd --auth-file /tmp/auth.tmp \
    ; rm /tmp/auth.tmp
```

For tools that strictly require a file argument. The `>` redirect
satisfies the terminal-aware safe form. **Always clean up** the
`/tmp` file with `rm`.

Caveat: a *follow-up* tool call doing `cat /tmp/auth.tmp` would slip
through the hook (path not in `SECRET_FILES_BASH_RE`). Don't write
follow-up commands that read the file; consume it within the same
chain.

### P8 -- clipboard for human flow

```bash
op read 'op://Vault/Item/credential' | pbcopy
```

For "load my clipboard so I can paste into a browser." The clipboard
is a human-side handoff, not a Claude-internal pattern.

---

## Anti-patterns (these will be blocked)

Each anti-pattern below maps to a rule in the spec
(`docs/specs/S-62-secret-guard-pretooluse-hook.md` § Cases). The
hook's block message identifies the rule that fired in the header
(e.g. `BLOCKED: secret leak (S-62/B5)`), and the recipe shown is
tailored to that rule.

| Anti-pattern | Rule | Fix |
|---|---|---|
| Bare `op read 'op://...'` | **B1** | P2 capture, P6 process-sub, or P7 redirect |
| `op read \| paste-token` (or `\| jq`, `\| tee` without final `>`, `\| grep`, `\| bash`, `\| xargs`) | **B1** | Same; pipes to stdout-echoing consumers leak via the consumer |
| Bare `secret-cache-read NAME` | **B2** | P2 capture; for registered vars, just use `$VAR` (P1) |
| `op item get NAME --field X --reveal`, `op signin --raw`, `op connect token create`, `op service-account create` | **B1** | Same as `op read` |
| `security find-generic-password -ws SVC -a $USER` (or `-w` bare) | **B2b** | Capture into VAR or redirect |
| `gh auth token` | **B2c** | Capture: `GH=$(gh auth token)` |
| `gpg --decrypt file.gpg`, `openssl enc -d ...`, `openssl rsautl/pkeyutl -decrypt` | **B2d** | Redirect plaintext to file |
| `echo $CLOUDFLARE_API_TOKEN`, `printf "key=%s" "${MY_API_KEY}"` | **B3** | Pass the var to a consumer that uses it (P1); never echo |
| `cat <<<"$OP_SERVICE_ACCOUNT_TOKEN"` (here-string) | **B3.5** | Pass via arg; don't here-string a secret |
| Bare `env`, `printenv`, `set` (no args) | **B4a** | Inspect specific vars (`echo $X`, `printenv X`); if dump needed, `> file` |
| `printenv CLOUDFLARE_API_TOKEN` | **B4b** | Don't print it; reference the var |
| `declare -p X`, `typeset -p X`, `export -p` | **B4c** | Redirect to file; capture |
| `cat ~/.config/fish/conf.d/secrets.fish`, `cat ~/.netrc`, `cat ~/.ssh/id_ed25519`, `cat ~/.kube/config`, etc. | **B5** | `dotfiles secret list` for names; read `.tmpl` source for refs |
| `cat <<EOF\n$CLOUDFLARE_API_TOKEN\nEOF` (unquoted heredoc) | **B6** | Quote the marker (`<<'EOF'`) to disable expansion, or pass via arg |
| `http POST .../auth Authorization:"Bearer sk-ant-..."` (literal credential in command) | **B7** | Replace literal with `$VAR` ref |
| `python -c "...os.environ['SECRET_NAME']..."` (or node/ruby/perl/deno equivalents) | **B8** | Redirect interpreter output, or pass as arg via `--token "$VAR"` |
| `Read /Users/.../.netrc` (or any secret-bearing path) | **R1** | Read the `.tmpl` source instead |
| Edit/Write whose new_string contains a credential pattern | **W1** | Replace literal with `${VAR}` / `op://...` / `$(op read ...)`; if a test fixture, name it `tests/secret-guard.sh` |
| Edit whose old_string contains a credential pattern | **W2** | Rotate the credential FIRST, then edit; the diff echoes old_string into the transcript |

```bash
# Examples of what gets blocked:
op read 'op://Vault/Item/credential'
op read 'op://...' | jq -r .field
echo $CLOUDFLARE_API_TOKEN
env
printenv OP_SERVICE_ACCOUNT_TOKEN
declare -p CLOUDFLARE_API_TOKEN
cat ~/.netrc
cat ~/.ssh/id_ed25519                       # .pub is allowed
cat <<EOF
$CLOUDFLARE_API_TOKEN
EOF
http POST .../auth Authorization:"Bearer sk-ant-api03-xxx..."
op item get "X" --reveal
security find-generic-password -ws SVC -a "$USER"
gh auth token
gpg --decrypt secret.gpg
python -c "import os; print(os.environ['CLOUDFLARE_API_TOKEN'])"
```

For any block, run `dotfiles secret-guard explain '<your command>'`
to see the rule-specific recipe before retrying. The block message
also prints the relevant snippet inline.

---

## Bypass marker

For genuinely-needed exceptions:

```bash
op read 'op://X/Y/z' | jq -r .field   # secret-guard: allow
```

Use sparingly. Every bypass-marker use means a secret value lands in
the transcript by your explicit choice.

---

## See also

- `docs/specs/S-62-secret-guard-pretooluse-hook.md` -- the spec
- `home/dot_claude/hooks/secret-guard/executable_secret-guard.sh` -- the hook source
- `tests/secret-guard.sh` -- the 100-case test matrix
- `~/.cache/claude-secret-guard.log` -- audit log (timestamps + reasons, no values)
