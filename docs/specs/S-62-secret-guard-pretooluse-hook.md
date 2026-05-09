---
id: S-62
title: secret-guard hook prevents Claude from leaking 1Password secrets into the session transcript
type: security
status: done
date: 2026-05-09
---

# S-62: secret-guard hook (anti-leak)

Three Claude Code hooks (PreToolUse + PostToolUse + Stop) that prevent
the assistant from causing a 1Password (or generic credential) value
to land in the JSONL session transcript. Companion to claude-guardrails'
`scan-secrets.sh` (which only inspects user prompts) and to S-45 (the
human-discipline rule that says "never echo resolved secret values").

## Problem

S-45 ratified the discipline: never let a resolved secret reach
stdout/stderr where it can be captured into a transcript. Discipline
rules are enforceable in repo code (review, shellcheck, manual audit)
but **not enforceable against Claude Code itself**. The assistant
happily runs `op read 'op://Personal/opencode-go/credential' |
paste-token`, `cat ~/.config/fish/conf.d/secrets.fish`, `echo "Loading
$CLOUDFLARE_API_TOKEN"`, or `env`/`printenv` (no args), each of which
deposits the resolved value into `~/.claude/projects/.../*.jsonl` where
it persists indefinitely and may be re-fetched by future sessions or
upstream telemetry.

S-62 closes the gap by intercepting Claude's outbound tool calls and
returning tool results.

## Threat model

The asset: any resolved credential value (1Password secret, AWS access
key, GitHub token, Anthropic / OpenAI API key, etc.).

The leak surface: the JSONL transcript, which captures (a) Claude's
text responses, (b) every tool call's `tool_input` verbatim, and
(c) every tool call's `tool_response` (stdout / stderr / file content
/ diff). The transcript persists on disk and is the input to
`/compact`, future sessions resuming, and any upstream telemetry.

| # | Asset                                                             | Vector blocked                                                                |
|---|-------------------------------------------------------------------|-------------------------------------------------------------------------------|
| 1 | 1P values resolved by `op read` / `op item get` / cache reads     | Bash command whose stdout/stderr reaches the topmost shell                    |
| 2 | Env vars holding credentials (`*_TOKEN`, `*_KEY`, `OP_*`)         | `echo`/`printf`/`printenv` of the var; bare `env`/`set`/`declare -p`          |
| 3 | Rendered secret-bearing files (`secrets.fish`, `.netrc`, `.aws/credentials`, `~/.config/op/*`, SSH private keys, `.pem`/`.kube`/`.docker`/`.npmrc`/`.git-credentials` etc.) | Bash `cat`-class against them; Read tool against them                         |
| 4 | Resolved credentials being written into committed files            | Edit/Write/MultiEdit `new_string` / `old_string` / `content` matching a credential pattern |

Out of threat model: the user explicitly writing the resolved value to
a file and later `cat`-ing it (user opt-in); a tool deliberately
writing to `/dev/tty`; `set -x`/`set -v` echoing the `op://`
*reference* (refs are not secrets); MCP write paths to Drive / Notion /
Gmail (separate spec).

## Approach

Three Claude Code hook events, three companion scripts, one shared
pattern set, one audit log.

```
                        ┌──────────────────────────┐
   user prompt   ──────▶│  UserPromptSubmit        │ (claude-guardrails scan-secrets, NOT S-62)
                        └──────────────┬───────────┘
                                       ▼
                        ┌──────────────────────────┐
                        │       Claude LLM         │
                        └──────────────┬───────────┘
                                       ▼
   ┌── BLOCK rc=2 ──────┐    ┌──────────────────────────┐
   │  rule-aware msg    │◀───│  PreToolUse              │  S-62: secret-guard.sh
   │  to stderr         │    │  17 rules, terminal-aware│
   └────────────────────┘    └──────────────┬───────────┘
                                       ▼ allow
                        ┌──────────────────────────┐
                        │   tool execution         │  (Bash / Read / Edit / Write / MultiEdit)
                        └──────────────┬───────────┘
                                       ▼
   ┌── WARN to stderr ──┐    ┌──────────────────────────┐
   │  + audit log       │◀───│  PostToolUse             │  S-62: secret-guard-post.sh
   │  POST-LEAK entry   │    │  pattern scan response   │
   └────────────────────┘    └──────────────┬───────────┘
                                       ▼
                        ┌──────────────────────────┐
                        │  Claude response (text)  │
                        └──────────────┬───────────┘
                                       ▼
   ┌── WARN to stderr ──┐    ┌──────────────────────────┐
   │  + audit log       │◀───│  Stop                    │  S-62: secret-guard-stop.sh
   │  STOP-LEAK entry   │    │  scan last assistant msg │
   └────────────────────┘    └──────────────┬───────────┘
                                       ▼
                        ┌──────────────────────────┐
                        │   JSONL transcript       │
                        │   (~/.claude/projects)   │
                        └──────────────────────────┘
```

**PreToolUse** is the primary defense (block before damage). **PostToolUse**
+ **Stop** are detection-only safety nets that catch leaks PreToolUse
cannot see (Read of an unlisted path, Bash whose stdout legitimately
echoes a token, Claude generating a secret in markdown response text).

Three architectural choices drive the design:

1. **Terminal-aware safe-form rule** for any "call that prints a
   secret to stdout" rule. A pipeline is safe iff (a) capture form
   (`$(...)` / backticks / `<(...)`), (b) any stdout redirect
   (`>`/`>>`/`&>`) anywhere in the same quote-aware segment, or
   (c) last stage in the no-echo allowlist (`pbcopy`/`xclip`/`wl-copy`).
   Earlier loose rule ("any pipe is safe") was disproved by the user
   running `op read 'op://...' | paste-token`, which echoes each char
   of stdin. Earlier strict rule ("only redirect or clipboard") was
   over-restrictive and blocked legitimate `op read X | jq -r .field
   > file`. Terminal-aware threads the needle.

2. **Quote-aware segment splitting** in the helper. Naive split on
   `;|&&|||` was breaking commands like `python -c "import os; print(...)"`
   where the `;` is inside a string, not a logical separator. An awk
   char-walker tracks single/double-quote state and only treats top-level
   delimiters as separators.

3. **Mode switch** (strict / warn-only / off). Lets a user enable
   warn-only on a fresh machine for a day, see what would block, then
   promote to strict. Also: debug escape via `off`.

## Architecture

### Three hook scripts

| Script                                                | Hook event   | Action on hit                               |
|-------------------------------------------------------|--------------|---------------------------------------------|
| `secret-guard.sh`                                     | PreToolUse   | exit 2 (strict) / exit 0 + warn (warn-only) |
| `secret-guard-post.sh`                                | PostToolUse  | warn-only (always exit 0)                   |
| `secret-guard-stop.sh`                                | Stop         | warn-only (always exit 0)                   |

All deployed to `~/.claude/hooks/secret-guard/` via chezmoi. Sources
in `home/dot_claude/hooks/secret-guard/`.

### Registration: additive merge in `modify_settings.json`

`home/dot_claude/modify_settings.json` is a chezmoi `modify_` script
(S-36) that owns the personal overlay of `~/.claude/settings.json`.
For S-62 it appends three matchers under `hooks.PreToolUse`
(`Bash`, `Read`, `Edit|Write|MultiEdit`), one matcher under
`hooks.PostToolUse` (`Bash|Read|Edit|Write|MultiEdit`), and one entry
under `hooks.Stop`. Each entry is keyed by a unique marker
(`secret-guard/secret-guard.sh`, `secret-guard-post.sh`,
`secret-guard-stop.sh`) for dedup-on-re-apply. Idempotency check
`f(f(x)) == f(x)` is a plumbing test.

### Self-test on apply

`home/.chezmoiscripts/run_onchange_after_secret-guard-test.sh.tmpl`
embeds a hash of all three hook source files via chezmoi's `include`
template function. When any of them changes, this script re-runs at
the next apply and invokes `tests/secret-guard.sh` against the deployed
hook. Failures surface via `lib.sh warn` in the apply summary.

On the first successful apply (marker file
`~/.cache/secret-guard.first-run-shown`), it also prints a one-time
banner pointing at the cheatsheet and `dotfiles secret-guard` CLI.

### CLI: `dotfiles secret-guard`

The `dotfiles` fish function gains a `secret-guard` (alias `sg`)
subcommand with seven verbs documented in §Operations.

## Cases

Each rule is described as: **leak scenario → why it leaks → detection
→ safe form → tests**. Test IDs reference `tests/secret-guard.sh`.

### B1 -- 1Password CLI verbs that print to stdout

- **Leak scenario**: bare `op read 'op://Vault/Item/credential'`,
  `op item get NAME --field credential --reveal`, `op signin --raw`,
  `op connect token create`, `op service-account create`. Any pipe
  to a stdout-echoing consumer (`| paste-token`, `| jq`, `| tee
  /tmp/x`, `| grep`, `| bash`, `| xargs`).
- **Why it leaks**: each verb writes the value to stdout. Bash tool
  captures stdout into `tool_use_result`; transcript stores it.
- **Detection**: regex `op[[:space:]]+(read|item[[:space:]]+get|signin[[:space:]]+(--raw|-r)|connect[[:space:]]+token[[:space:]]+create|service-account[[:space:]]+create)`
  + `is_safe_secret_call` helper (terminal-aware).
- **Safe form**: capture (P2: `TOKEN=$(op read 'op://...')`), redirect
  anywhere in pipeline (P7: `... > /tmp/auth`), process substitution
  (P6: `<(op read ...)`), or clipboard sink. For pre-loaded vars,
  prefer P1 (`$CLOUDFLARE_API_TOKEN`).
- **Tests**: 01-09 (block variants, including the user's `paste-token`
  repro at 02), 26-28 (allow redirect), 29-30 (allow capture), 31-33
  (allow clipboard), 34-37 (allow terminal-aware redirect anywhere),
  62-63 (block op alternates), 83 (allow `op signin` without `--raw`),
  84 (allow `op item get --reveal > file`), 105 (allow P6).

### B2 -- `secret-cache-read NAME`

- **Leak scenario**: bare `secret-cache-read CLOUDFLARE_API_TOKEN`,
  pipe to stdout-echoing consumer.
- **Why**: prints cached value to stdout.
- **Detection**: regex `secret-cache-read` + `is_safe_secret_call`.
- **Safe form**: P2 (capture). For registered vars, P1 (just
  reference the env var directly; fish loads them at startup).
- **Tests**: 10-11 (block), 38 (allow capture).

### B2b -- macOS Keychain raw read

- **Leak scenario**: `security find-generic-password -ws SVC -a $USER`
  or `security find-generic-password -s SVC -a $USER -w`.
- **Why**: `-w`/`-ws` flags print the password to stdout.
- **Detection**: regex `security[[:space:]]+find-generic-password[[:space:]][^|]*-w(s|[[:space:]]|$)`
  + `is_safe_secret_call`.
- **Safe form**: capture into `VAR=$(security find-generic-password
  -ws SVC -a $USER)` or redirect.
- **Tests**: 64-65 (block), 85 (allow capture).

### B2c -- `gh auth token`

- **Leak scenario**: bare `gh auth token`.
- **Why**: prints the GitHub CLI's stored token.
- **Detection**: regex `gh[[:space:]]+auth[[:space:]]+token` +
  `is_safe_secret_call`.
- **Safe form**: capture (`GH=$(gh auth token)`) or pipe to clipboard.
- **Tests**: 74 (block), 90 (allow capture).

### B2d -- decryption commands

- **Leak scenario**: `gpg --decrypt secret.gpg`, `gpg -d`, `openssl
  enc -d ...`, `openssl rsautl -decrypt`, `openssl pkeyutl -decrypt`.
- **Why**: writes plaintext to stdout. Plaintext is treated as
  secret by default.
- **Detection**: regex
  `gpg[[:space:]]+(-d|--decrypt)|openssl[[:space:]]+(enc[[:space:]]+[^|]*-d|rsautl[[:space:]]+[^|]*-decrypt|pkeyutl[[:space:]]+[^|]*-decrypt)`
  + `is_safe_secret_call`.
- **Safe form**: redirect to file (`> /tmp/plain`) or capture.
- **Tests**: 75-76 (block), 94 (allow redirect).

### B3 -- `echo`/`printf`/`print` of a secret-named variable

- **Leak scenario**: `echo $CLOUDFLARE_API_TOKEN`, `printf "key=%s"
  "${MY_API_KEY}"`, etc.
- **Why**: variable expansion to stdout.
- **Detection**: regex
  `(echo|printf|print)[[:space:]][^|]*\$\{?<SECRET_NAME_RE>` where
  `SECRET_NAME_RE` matches `CLOUDFLARE_API_TOKEN`,
  `R2_SECRET_ACCESS_KEY`, `OP_SERVICE_ACCOUNT_TOKEN`, `OP_SESSION_*`,
  or any `*_TOKEN`/`*_SECRET`/`*_PASSWORD`/`*_PASSPHRASE`/`*_API_KEY`/`*_PRIVATE_KEY`.
- **Safe form**: pass the value through without printing it (`curl
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" url`); do NOT
  `echo` it for debugging.
- **NOT terminal-aware** by design (accepted false positive: `(echo
  $TOKEN) > /dev/null` is blocked though safe; bypass marker handles
  it).
- **Tests**: 12 (block `echo`), 13 (block `printf`), 42 (allow `echo
  $PATH` -- non-secret name).

### B3.5 -- here-string of a secret-named variable

- **Leak scenario**: `cat <<<"$OP_SERVICE_ACCOUNT_TOKEN"`.
- **Why**: here-string body expands the variable; `cat` prints to
  stdout.
- **Detection**: regex `<<<[[:space:]]*[\"']?[^\"']*<SECRET_DEREF_RE>`.
- **Safe form**: avoid here-strings for secret-bearing vars; pass via
  arg or env directly.
- **Tests**: 14.

### B4a -- bare `env` / `printenv` / `set`

- **Leak scenario**: `env`, `printenv`, `set` (no args).
- **Why**: dumps every variable in scope to stdout, including
  credential-bearing ones.
- **Detection**: regex `(env|printenv|set)([[:space:]]*$|[[:space:]]*[;&|]|[[:space:]]*>)`
  + `is_safe_secret_call`. Wrappers like `env -u FOO bar`, `env A=B
  cmd`, `set -e`, `set --` are intentionally allowed via the
  terminator-class exclusion.
- **Safe form**: inspect specific vars (`echo $NON_SECRET_VAR`,
  `printenv NON_SECRET_VAR`); for legitimate full-dump, redirect to
  file (`env > /tmp/env-dump`).
- **Tests**: 15-16 (block bare env / printenv), 70 (block bare set),
  39-40 (allow env wrappers), 86-88 (allow set with flags), 89
  (allow `set > file`).

### B4b -- `printenv NAME` of a secret-bearing variable

- **Leak scenario**: `printenv OP_SERVICE_ACCOUNT_TOKEN`.
- **Why**: prints just that variable's value.
- **Detection**: regex `printenv[[:space:]]+<SECRET_NAME_RE>` (hard
  block, no terminal-aware path because the value goes straight to
  stdout regardless).
- **Safe form**: don't print it; reference the variable instead.
- **Tests**: 17.

### B4c -- `declare -p` / `typeset -p` / `export -p`

- **Leak scenario**: `declare -p OP_SERVICE_ACCOUNT_TOKEN`,
  `typeset -p CLOUDFLARE_API_TOKEN`, `export -p`.
- **Why**: print variable definitions including resolved values.
- **Detection**: regex `(declare|typeset|export)[[:space:]]+-p` +
  `is_safe_secret_call`.
- **Safe form**: redirect to file (`declare -p X > /tmp/dec`) or
  capture.
- **Tests**: 71-73 (block).

### B5 -- `cat`-class on secret-bearing files

- **Leak scenario**: `cat ~/.config/fish/conf.d/secrets.fish`,
  `head ~/.netrc`, `less ~/.aws/credentials`, `cat ~/.ssh/id_ed25519`,
  `cat ~/.kube/config`, etc.
- **Why**: prints file contents to stdout. The path list covers files
  whose contents are credential values on a configured machine.
- **Detection**: regex
  `(cat|bat|head|tail|less|more|xxd|hexdump)[[:space:]][^|]*<SECRET_FILES_BASH_RE>`
  where `SECRET_FILES_BASH_RE` covers:
  - `*/conf.d/secrets.fish`, `*/.netrc`, `*/.aws/credentials`
  - `*/.config/op/*`, `*.local/*.{env,secrets,tokens}`
  - `*/.ssh/id_*` (excluding `*.pub`; positive class excludes `.`
    after the name)
  - `*/.kube/config`, `*/.docker/config.json`
  - `*/.npmrc`, `*/.pypirc`
  - `*/.cargo/credentials`, `*/.gem/credentials`
  - `*/.git-credentials`, `*/.config/gh/hosts.yml`
  - `*/.config/gcloud/application_default_credentials.json`
  - `*.pem`, `*.p12`, `*.pfx`
- **Safe form**: `dotfiles secret list` for registered names + cache
  status; read the `.tmpl` source (it has `op://` refs, not values).
- **Tests**: 18-20 (block standard files), 60 (block SSH key), 66
  (block kube config), 80 (allow `id_*.pub`).

### B6 -- heredoc with unquoted marker expanding a secret-bearing var

- **Leak scenario**: `cat <<EOF\n$CLOUDFLARE_API_TOKEN\nEOF`.
- **Why**: unquoted heredoc marker performs `$VAR` expansion; cat
  prints the body to stdout.
- **Detection**: heredoc-marker regex
  `(^|[^<])<<-?[[:space:]]*[A-Za-z_]` AND `<SECRET_DEREF_RE>` anywhere
  in the command. Quoted markers (`<<'EOF'`, `<<"EOF"`) preserve the
  body literally; the regex doesn't match them because `'` and `"`
  aren't `[A-Za-z_]`.
- **Safe form**: quote the marker (`<<'EOF'`) for a literal body, or
  pass the secret as an arg.
- **Tests**: 55 (block unquoted marker), 56 (allow quoted marker).

### B7 -- literal credential embedded in the Bash command itself

- **Leak scenario**: `http POST .../auth Authorization:"Bearer
  sk-ant-api03-..."`, `aws s3 ls --access-key-id AKIA<...EXAMPLE>`.
- **Why**: the `tool_input.command` string is captured into the
  transcript verbatim. The literal credential pattern bytes are in
  the JSONL even before exec.
- **Detection**: jq-based pattern scan against the shared
  `~/.claude/hooks/patterns/secrets.json` (claude-guardrails-owned;
  AWS AKIA, GitHub PAT, sk-ant, sk-(proj-)?, Google API key, Slack,
  Stripe, 1P SA `ops_`, PEM private-key blocks, 64-hex private keys,
  `api_key=value`-style assignments).
- **Safe form**: replace the literal with a `$VAR` ref and ensure the
  variable is in env (P1) or captured first (P2).
- **Tests**: 53-54 (block sk-ant, AKIA in command).

### B8 -- interpreter `-c`/`-e` script reading a secret-bearing env var

- **Leak scenario**: `python -c "import os; print(os.environ['CLOUDFLARE_API_TOKEN'])"`,
  `node -e "console.log(process.env.OP_SERVICE_ACCOUNT_TOKEN)"`,
  `ruby -e "puts ENV['ANTHROPIC_API_KEY']"`, similar for `perl`,
  `deno`.
- **Why**: interpreter writes the value to stdout. Different syntax
  per language, same outcome.
- **Detection**: three-signal layered match:
  1. `(python[23]?|node|deno|ruby|perl)[[:space:]]+(-c|-e)[[:space:]]`
  2. `(os\.environ|process\.env|ENV\[|\$ENV\{)`
  3. `<SECRET_NAME_RE>`
  All three must be present. Then `is_safe_secret_call`.
- **Safe form**: redirect (`python -c '...' > /tmp/out`) or capture
  in shell first and pass via arg.
- **Tests**: 77-79 (block python/node/ruby), 91 (allow no env access),
  92 (allow non-secret env var like PATH), 93 (allow with redirect).

### R1 -- Read tool against a secret-bearing path

- **Leak scenario**: Read `tool_input.file_path =
  /Users/.../.config/fish/conf.d/secrets.fish` etc.
- **Why**: Read tool returns file content into `tool_use_result`,
  which lands in the transcript.
- **Detection**: case-glob match against the same path list as B5.
  SSH public keys (`*.pub`) are explicitly allow-listed FIRST so the
  broader `id_*` glob doesn't catch them.
- **Safe form**: read the `.tmpl` template instead (refs, not values);
  use `dotfiles secret list` for registered names.
- **Tests**: 21-23 (block secrets.fish, .netrc, credentials), 44
  (allow random non-listed file), 45 (allow `.tmpl` source), 61
  (block SSH private key), 67-69 (block more credential files), 80-82
  (allow SSH public keys).

### W1 -- Edit/Write/MultiEdit content with a credential pattern

- **Leak scenario**: Claude writing a file whose `new_string` /
  `content` / `edits[].new_string` contains a literal credential.
- **Why**: the diff output of Edit/Write/MultiEdit is captured into
  the transcript; future readers (compaction, resume, telemetry)
  see the pattern. Plus, the file lands on disk.
- **Detection**: jq-based scan against `patterns/secrets.json`. Path-
  based exemption FIRST for test fixtures (`*/tests/secret-guard.sh`,
  `*/docs/secret-handling-cheatsheet.md`) -- those files contain
  example credentials by design.
- **Safe form**: replace the literal with `${VAR}` (env-var ref),
  `op://...` (1P ref resolved at template-render time), or
  `$(op read ...)` (capture).
- **Tests**: 24-25 (block sk-ant, AKIA in content), 110-111 (allow
  fixture-path edits), 112 (block same payload at non-exempt path),
  46 (allow normal markdown).

### W2 -- Edit/MultiEdit `old_string` carrying a literal credential

- **Leak scenario**: Claude trying to REMOVE a hardcoded credential
  from a file (e.g. cleaning up a leak); the `old_string` contains
  the literal value, which the Edit diff echoes into the transcript.
- **Why**: the diff carries old_string into the transcript; even
  though Claude is doing the right thing (removing a leak), the act
  of removal still echoes the value once.
- **Detection**: same jq scan, applied to `old_string` and
  `edits[].old_string`.
- **Safe form**: rotate the credential first (so the old value is
  worthless), THEN edit the file. Or: use a redaction pattern that
  doesn't match (e.g. delete the line with `sed` via Bash and
  bypass-marker).
- **Tests**: 57.

## Canonical patterns: how Claude USES a secret

The hook blocks "secret value lands in transcript." It does not block
*using* a secret. Eight canonical patterns documented in
`docs/secret-handling-cheatsheet.md`; brief recap:

| Pattern | When to use                                                         | Example |
|---------|---------------------------------------------------------------------|---------|
| **P1**  | Pre-loaded env var (CLOUDFLARE_API_TOKEN, OP_SERVICE_ACCOUNT_TOKEN) | `curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" url` |
| **P2**  | Secret not pre-loaded; one-shot use, single Bash call               | `TOKEN=$(op read 'op://...'); curl -H "Authorization: Bearer $TOKEN" url` |
| **P3**  | (anti-pattern) capture in call N, use in call N+1                   | does NOT work; bash subshells don't share env across Claude tool calls |
| **P4**  | Consumer reads from env                                             | `TOKEN=$(op read 'op://...') my-app --use-env` |
| **P5**  | Complex composition                                                 | `TOKEN=$(op read 'op://...') bash -c 'curl -H "Authorization: Bearer $TOKEN" url'` |
| **P6**  | Consumer reads stdin (`-H @-`-style)                                | `curl -H @<(op read 'op://...') url` |
| **P7**  | Consumer needs a file argument                                      | `op read 'op://...' > /tmp/auth && cmd /tmp/auth; rm /tmp/auth` |
| **P8**  | Human paste flow (clipboard)                                        | `op read 'op://...' \| pbcopy` |

Each P-pattern is tested in the matrix (100-106).

## Test matrix

`tests/secret-guard.sh`: self-contained runner, 112 cases, 112/112
passing on Hans-Air-M4 as of 2026-05-09. Runs against the deployed
hook (or the source via `HOOK=...`), used by both ad-hoc verification
(`dotfiles secret-guard test`) and the `run_onchange_after_*` self-test.

| Section                                       | Tests       | Asserts                                        |
|-----------------------------------------------|-------------|------------------------------------------------|
| 1. BLOCK -- op read variants                  | 01-09       | bare; pipes to paste-token / tee / jq / grep / bash / xargs; `2>&1`; stderr-only redirect |
| 2. BLOCK -- secret-cache-read                 | 10-11       | bare; pipe to tee                              |
| 3. BLOCK -- echo/printf/heredoc of secret var | 12-14       | echo, printf, here-string                      |
| 4. BLOCK -- env-dump variants                 | 15-17       | bare env, bare printenv, printenv NAME         |
| 5. BLOCK -- cat-class on secret files         | 18-20       | secrets.fish, .netrc, .aws/credentials         |
| 6. BLOCK -- Read tool                         | 21-23       | same path list                                 |
| 7. BLOCK -- Edit/Write literal credentials    | 24-25       | sk-ant, AKIA in content                        |
| 7b. BLOCK -- audit-pass (FN1/FN2/FN3)         | 53-55, 57   | literal in command, heredoc expansion, old_string |
| 7c. BLOCK -- ultrathink Tier 1 (op alts/SSH)  | 60-65       | SSH key, op item get, op signin --raw, security keychain |
| 7d. BLOCK -- ultrathink Tier 2 (more files)   | 66-79       | kube/docker/npmrc/pem; set/declare; gh/gpg/openssl; python/node/ruby |
| 8. ALLOW -- safe forms for op read            | 26-33       | redirect, capture, clipboard                   |
| 9. ALLOW -- v3 terminal-aware                 | 34-37       | redirect anywhere in pipeline                  |
| 10. ALLOW -- non-secret patterns              | 38-46       | env wrappers, dotfiles secret list, $PATH, bypass marker, .tmpl read, normal write |
| 10b. ALLOW -- audit-pass negatives            | 56          | quoted heredoc                                 |
| 10c. ALLOW -- ultrathink boundary cases       | 80-95       | SSH public keys; op signin no --raw; set -e/set --; python no env; gpg redirect |
| 10d. ALLOW -- canonical patterns P1-P7        | 100-106     | curl with env var, capture-then-use, bash -c, process sub, file handoff |
| 11. PLUMBING                                  | 47-52       | shellcheck; idempotency f(f(x))==f(x); managed; fail-open on missing jq; fail-open on bad JSON |
| 12. v3.4 -- A1/D1/B1/B2                       | 110-117     | path exemption; audit log format; PostToolUse warns; Stop warns |
| 12e. v3.5 -- MODE / per-rule guidance         | 120-123     | warn-only exits 0 with WARN-ONLY header; off silent; B5 message has B5 text; B7 message has B7 text |

## Operations

### CLI (`dotfiles secret-guard <verb>`, alias `sg`)

| Verb                  | What it does |
|-----------------------|--------------|
| `explain '<cmd>'`     | Pipe a synthetic Bash tool_input through the deployed hook; report `ALLOW (rc=0)` / `BLOCK (rc=2)` plus the rule-aware block message. Use to dry-run any command. |
| `test`                | Run `tests/secret-guard.sh` against the deployed hook (`HOOK=~/.claude/hooks/...`). |
| `log [filter]`        | Tail the audit log. Filters: `--blocks`, `--bypasses`, `--leaks` (Stop+Post), `--all`. |
| `tail`                | `tail -F` on the audit log. |
| `mode [s\|w\|o]`      | Show or set the hook mode. Without arg, reads `~/.config/secret-guard/mode`. With arg, writes it. |
| `audit-transcripts`   | Scan `~/.claude/projects/**/*.jsonl` against `patterns/secrets.json`; report file + pattern names. Read-only. |
| `doctor`              | Health check: deployed hooks executable, jq present, patterns/secrets.json present, log dir writable, modify_settings.json in source. |

### Audit log

Path: `~/.cache/claude-secret-guard.log`. Rotation: cap at 1 MiB,
single `.1` backup. Format:

```
[<UTC ISO ts>] [<STATUS>] [<session_id>] [<tool>] <reason>
```

`STATUS` ∈ `BLOCK` (PreToolUse rule fired in strict mode) | `BYPASS`
(user used `# secret-guard: allow` or path-exempt write) | `STOP-LEAK`
(Stop hook found a pattern in last assistant message) | `POST-LEAK`
(PostToolUse hook found a pattern in tool_response). The reason
includes the rule ID (e.g. `[B7] command contains a literal credential
(Anthropic API key)`). The log records timestamps, status,
session/tool, and pattern names only -- never the resolved value, the
offending command, or file content.

### Mode switch

Source-of-truth precedence: `SECRET_GUARD_MODE` env var first, then
`~/.config/secret-guard/mode` file, default `strict`.

| Mode        | Behavior on rule hit                                      | Use case                                  |
|-------------|-----------------------------------------------------------|-------------------------------------------|
| `strict`    | exit 2, block, stderr message                             | default                                   |
| `warn-only` | exit 0, log + stderr `WARN-ONLY: secret leak (S-62/<rule>)` | progressive adoption: enable on a new machine, run for a day to see what would block, promote |
| `off`       | exit 0 immediately, silent                                | debug escape hatch; never use in normal workflow |

### Bypass marker

Append `# secret-guard: allow` (or `secret-guard: allow`) anywhere in
a Bash command or Edit/Write content to bypass the hook for that one
call. Every bypass is logged as `[BYPASS]` in the audit log -- use
sparingly because each one is a deliberate leak by user choice.

### Fail-open

Hook exits 0 silently if (a) `jq` is missing on PATH (`command -v jq`
fails), or (b) the input JSON is malformed. Tested at plumbing tests
51-52. Better to under-guard than to break legitimate work on a broken
install.

### Self-test on apply

`run_onchange_after_secret-guard-test.sh.tmpl` includes a SHA hash of
each hook source via chezmoi's `include` template function. When any
hook source changes, the hash changes, chezmoi re-runs the script,
which invokes `tests/secret-guard.sh` against the **deployed** hook.
Failures surface in the apply summary via `lib.sh warn`. First
successful run also prints a one-time onboarding banner.

Skipped in `headless` mode (no Claude Code = no hook to test).

## Out of scope

Identified across iterations and explicitly chosen NOT to fix because
they are (a) low-likelihood in the user's environment, (b) unsolvable
inside PreToolUse, or (c) better handled by a separate spec.

### Tier 3 (real but rare or unsolvable)

- **Other password-manager / cloud-secret CLIs**: `pass`, `bw get`,
  `lpass show`, `vault kv get -field`, `aws ssm get-parameter`,
  `aws secretsmanager get-secret-value`, `gcloud secrets versions
  access`, `kubectl get secret -o jsonpath`. The user's environment
  is 1Password + macOS Keychain + GitHub CLI; add a B-class rule per
  CLI when usage starts.
- **`${!VAR_NAME}` indirect expansion** (and `eval "echo \$$VAR"`,
  `printenv "$VARHOLDINGNAME"`). Bypasses the literal-name regex.
  Rare; would need a dynamic-name resolver to detect.
- **B3 / B3.5 / B6 not terminal-aware** by design. So `(echo $TOKEN)
  > /dev/null` is blocked though safe. Acceptable false positive
  (bypass marker is the escape; rare to need to redirect an echo of
  a secret variable).
- **Base64-encoded or otherwise-obfuscated secrets**. `echo c2stYW50...
  | base64 -d` bypasses B7, base64 decoder writes plaintext to stdout.
  No simple regex catches this.
- **Network side channels**: `curl -v -H "Authorization: Bearer
  $TOKEN" url` prints the expanded header in verbose mode. Edge case;
  bypass marker exists.
- **Filesystem-relocation leaks**: `op read X > /tmp/x; cat /tmp/x`.
  User opted in to writing the secret to a file; the follow-up `cat`
  on a non-listed path slips through. PreToolUse cannot reason about
  cross-call state.
- **`tee /dev/tty`** -- explicit terminal write inside an otherwise-
  safe pipeline. Bypass marker handles it.
- **`secrets.fish` rendered file content**: confirmed during audit to
  contain `op://` references and `secret-cache-read --batch`
  invocations, NOT resolved values. B5 still blocks reading it as
  defense-in-depth (refs are sensitive metadata: vault names, item
  IDs, field names) but this is not a strict leak.

### Other tool surfaces (separate spec when needed)

- **MCP tool matchers** (`mcp__*` write paths to Drive / Notion /
  Gmail / Slack / Cloudflare). Most pose a different leak surface
  (tool-result scanning would be needed).
- **NotebookEdit** (Jupyter cell editing). Cell content with a literal
  secret would slip through. Register a `NotebookEdit` matcher
  mirroring `Edit` if Jupyter usage starts on this machine.
- **Task** (sub-agent invocation). Claude could put a secret in a
  sub-agent prompt; the sub-agent's actions are also recorded.
  Recursive guarding needed.
- **WebFetch / WebSearch**. URL or query string with embedded secret.

### PreToolUse-fundamental limits

- **Tool-result REDACTION** (vs warn-only). Read-tool output and Bash
  stdout cannot be modified by PreToolUse. Closing this gap requires
  documented Claude Code response-modification protocol for
  PostToolUse, which doesn't exist as a stable surface yet.
- **Stderr-channel leaks from arbitrary tools**. Most consumers don't
  write the secret to stderr. `set -x` echoing the `op://` reference
  (not the resolved value) is acceptable; refs are not secrets.
- **Cross-session enforcement of bypass markers**. The marker is
  per-call. There is no allowlist of "bypassed forever."

## Definition of done (per S-44)

- [x] Spec frontmatter `status: done`
- [x] Tick in `docs/tasks.md`
- [x] Hostname-tagged entry in `docs/sync-log.md`
- [x] All 112 tests in `tests/secret-guard.sh` pass on Hans-Air-M4
- [x] shellcheck clean on all hook scripts and `modify_settings.json`
- [x] `chezmoi diff` shows no mutation of guardrails-owned entries
- [x] Self-test runs on every apply that touches a hook source
- [x] First-run banner appears once per machine
- [x] Cheatsheet (`docs/secret-handling-cheatsheet.md`) cross-refs
      this spec by case ID

## Changelog

Origin and iteration history. Detailed narrative lives in
`docs/sync-log.md`; this is the one-line summary.

| Version | Description                                                                                                  |
|---------|--------------------------------------------------------------------------------------------------------------|
| v1      | Initial PreToolUse hook. Loose pipe rule (any `op read \| <consumer>` allowed).                              |
| v2      | User reproduced `op read 'op://Personal/opencode-go/credential' \| paste-token` leak; tightened to "no pipes" |
| v3      | Terminal-aware rule: pipe is safe iff capture / redirect / no-echo allowlist. Reduced false positives.       |
| v3.1    | Pre-deploy audit closed FN1 (literal credentials in command), FN2 (heredoc expansion), FN3 (Edit old_string). |
| v3.2    | Ultrathink pass added Tier 1 (SSH keys, op alternates, macOS Keychain) and Tier 2 (more credential files, env-dump variants, gh, gpg/openssl, language interpreters). Quote-aware segment splitting. |
| v3.3    | Canonical patterns P1-P8 documented. `<()` process-substitution stripping. Block message inlines safe forms. New cheatsheet. |
| v3.4    | Defense-in-depth: Stop hook + PostToolUse hook (warn-only). Path exemption for test fixtures (A1). Audit log enrichment with `[STATUS] [session] [tool]` + bypass logging. `dotfiles secret-guard` CLI. CLAUDE.md cross-ref. chezmoi self-test on apply. |
| v3.5    | Per-rule block guidance (rule-aware recipes instead of generic patterns). `SECRET_GUARD_MODE` switch (strict/warn-only/off). Fish completions. `audit-transcripts` retroactive scanner. First-run banner. |
