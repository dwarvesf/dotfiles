#!/usr/bin/env bash
# secret-guard.sh - Claude Code PreToolUse hook.
#
# Blocks tool calls that would leak resolved 1Password secrets into the
# session transcript. Companion to claude-guardrails' scan-secrets.sh,
# which only inspects the user's prompt (UserPromptSubmit). This hook
# inspects Claude's outbound tool calls (Bash command, Read path,
# Edit/Write/MultiEdit content).
#
# Hook protocol: stdin = JSON with {tool_name, tool_input, ...}.
#   exit 0 -> allow
#   exit 2 -> block; stderr is shown to Claude as the block reason.
#
# Bypass marker: append "# secret-guard: allow" anywhere in the
# command/content. Use sparingly; prefer redirecting/piping output.
#
# Match rules (case-sensitive unless noted). Rules marked "terminal-
# aware" use the shared is_safe_secret_call helper, which treats a
# pipeline as safe iff (a) capture form (`$()` / backticks),
# (b) any stdout redirect (`>`, `>>`, `&>`) anywhere in the pipeline,
# or (c) last stage in the no-echo allowlist (pbcopy / xclip / wl-copy).
#
#   Bash 1. 1Password CLI verbs that print a value to stdout:
#          `op read`, `op item get`, `op signin --raw`, `op connect
#          token create`, `op service-account create`. Terminal-aware.
#   Bash 2. `secret-cache-read NAME`. Terminal-aware.
#   Bash 2b. macOS Keychain raw read: `security find-generic-password
#          -w / -ws`. Terminal-aware.
#   Bash 2c. `gh auth token`. Terminal-aware.
#   Bash 2d. Decryption: `gpg -d / --decrypt`, `openssl enc -d`,
#          `openssl rsautl -decrypt`, `openssl pkeyutl -decrypt`.
#          Terminal-aware.
#   Bash 3. echo|printf|print|cat <<<"...$VAR..." referencing a
#          secret-named variable. NOT terminal-aware (a known
#          accepted false-positive: `(echo $TOKEN) > /dev/null` is
#          blocked though safe).
#   Bash 4a. Bare `env` / `printenv` / `set` (no args) — dumps every
#          credential in scope. Terminal-aware. Wrappers (`env -u FOO
#          bar`, `set -e`, `set --`) are intentionally allowed.
#   Bash 4b. `printenv NAME` of a secret-bearing variable. Hard block.
#   Bash 4c. `declare -p`, `typeset -p`, `export -p` — print variable
#          definitions including resolved values. Terminal-aware.
#   Bash 5. cat|bat|head|tail|less|more|xxd|hexdump of known
#          secret-bearing files (see SECRET_FILES_BASH_RE for the
#          full list: secrets.fish, .netrc, .aws/credentials,
#          ~/.config/op/*, .env/.secrets/.tokens, SSH private keys
#          (id_* excluding .pub), .kube/config, .docker/config.json,
#          .npmrc, .pypirc, .cargo/.gem/.git-credentials, gh hosts.yml,
#          gcloud ADC, *.pem/*.p12/*.pfx).
#   Bash 6. Heredoc with UNQUOTED marker (`<<EOF`, `<<-EOF`) whose
#          body references a secret-named var. Quoted markers
#          (`<<'EOF'`, `<<"EOF"`) preserve the body literally and
#          are NOT blocked.
#   Bash 7. Bash command string itself contains a literal credential
#          matching the shared pattern set (Anthropic / OpenAI / AWS /
#          GitHub / Stripe / Slack / 1P SA / PEM / hex private key).
#          The command is in the transcript verbatim.
#   Bash 8. Interpreter -c/-e script (python/node/deno/ruby/perl) that
#          reads a secret-bearing env var. Heuristic combines the
#          interpreter form + env-access syntax + secret-named identifier.
#          Terminal-aware.
#   Read    file_path matches the same secret-bearing file list as
#          Bash 5; SSH public keys (`*.pub`, `*-cert.pub`) are
#          explicitly allow-listed first so the broader id_* match
#          doesn't catch them.
#   Edit/Write/MultiEdit    Scans new_string + old_string + content +
#          edits[].{new,old}_string against the shared pattern set
#          at ~/.claude/hooks/patterns/secrets.json. old_string is
#          included because the Edit diff echoes it into the transcript.
#
# Failure mode: if jq is missing or stdin is malformed JSON the hook
# fails open (exit 0). Better to under-guard than to block legitimate
# work on a broken install. Misses are surfaced via the apply log only.
#
# Audit log: ~/.cache/claude-secret-guard.log (UTC ISO timestamps).
set -u

INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
echo "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

# Mode selection (S-62 v3.5):
#   SECRET_GUARD_MODE env var > ~/.config/secret-guard/mode file > "strict".
# Modes:
#   strict     -- block on rule hit (exit 2). Default.
#   warn-only  -- log + emit warning to stderr but exit 0. Useful for
#                 progressive adoption on a new machine: see what would
#                 block before promoting to strict.
#   off        -- exit 0 immediately. Debug escape hatch.
SECRET_GUARD_MODE_FILE="${HOME}/.config/secret-guard/mode"
MODE="${SECRET_GUARD_MODE:-}"
if [ -z "$MODE" ] && [ -r "$SECRET_GUARD_MODE_FILE" ]; then
    MODE=$(tr -d '[:space:]' <"$SECRET_GUARD_MODE_FILE" 2>/dev/null)
fi
case "$MODE" in
    strict | warn-only) ;;
    off)
        # Off-mode: skip everything cleanly.
        exit 0
        ;;
    *)
        MODE="strict"
        ;;
esac

LOG="${HOME}/.cache/claude-secret-guard.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# Log rotation: cap at 1 MiB, keep one .1 backup. Cheap heuristic
# (stat once per hook invocation); failure is silent.
LOG_MAX_BYTES=1048576
if [ -f "$LOG" ]; then
    sz=$(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null || echo 0)
    if [ "${sz:-0}" -gt "$LOG_MAX_BYTES" ]; then
        mv -f "$LOG" "${LOG}.1" 2>/dev/null || true
    fi
fi

# Pull session/tool metadata for log entries. session_id appears at
# the top level of the input JSON for every hook event.
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TOOL_FOR_LOG=$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)

log_event() {
    # log_event STATUS REASON   -- STATUS in BLOCK | BYPASS
    printf '[%s] [%s] [%s] [%s] %s\n' \
        "$(date -u +%FT%TZ)" "$1" "$SESSION_ID" "$TOOL_FOR_LOG" "$2" \
        >>"$LOG" 2>/dev/null
}

# block REASON [RULE_ID]
# Emit a rule-aware block message to stderr, log to audit, then exit
# 2 (strict) or 0 (warn-only). RULE_ID drives the recipe shown to
# the user, so they get the relevant fix instead of a generic list.
block() {
    local reason="$1" rule="${2:-generic}"
    log_event "BLOCK" "[$rule] $reason"
    local label="BLOCKED"
    [ "$MODE" = "warn-only" ] && label="WARN-ONLY"
    # Short, human-readable headline per rule for the banner. The
    # rule code (B3, B6, ...) still gets logged in audit for grep
    # but no longer appears in the user-facing banner.
    local short
    case "$rule" in
    B1)   short="1Password value to terminal" ;;
    B2)   short="secret-cache-read to terminal" ;;
    B2b)  short="keychain password to terminal" ;;
    B2c)  short="gh auth token to terminal" ;;
    B2d)  short="decrypted plaintext to terminal" ;;
    B3)   short="echo of a secret variable" ;;
    B3.5) short="here-string with a secret" ;;
    B4a)  short="bare env / printenv / set dump" ;;
    B4b)  short="printenv of a secret variable" ;;
    B4c)  short="declare/typeset/export -p exposes secret" ;;
    B5)   short="cat-class read of a secret file" ;;
    B6)   short="heredoc body expands a secret variable" ;;
    B7)   short="literal credential in command" ;;
    B8)   short="interpreter reads a secret env var" ;;
    R1)   short="Read of a secret-bearing file" ;;
    W1 | W2) short="literal credential in Edit/Write" ;;
    *)    short="secret leak" ;;
    esac
    {
        echo
        echo "============= ${label}: ${short} ============="
        echo "$reason"
        echo
        case "$rule" in
        B1 | B2 | B2b | B2c | B2d)
            # Calls that print a secret to stdout. Terminal-aware safe forms.
            echo "Safe forms (this rule is terminal-aware -- any one is enough):"
            echo "  VAR=\$(<call>)              # capture into a variable"
            echo "  <call> > /tmp/secret        # redirect stdout to file"
            echo "  <call> | pbcopy             # clipboard sink (no echo)"
            echo "  ... | <consumer> > /tmp/x   # redirect ANYWHERE in pipeline"
            ;;
        B3 | B3.5 | B6)
            # Echo / printf / heredoc of a secret-named variable.
            echo "Don't print a secret-bearing variable. Pass it through instead:"
            echo "  curl -H \"Authorization: Bearer \$CLOUDFLARE_API_TOKEN\" url"
            echo "  cmd --token \"\$TOKEN\"          # arg expansion (literal \$VAR in cmd)"
            echo "  process_secret_in_subshell    # never echo to stdout"
            echo "Or, if you genuinely need to write the value to a file:"
            echo "  printf '%s' \"\$TOKEN\" > /tmp/x  # NOT terminal-aware; bypass needed"
            ;;
        B4a | B4b | B4c)
            # Env-dump variants: filter rather than dump.
            echo "Don't dump every variable. Inspect specific ones:"
            echo "  echo \$NON_SECRET_VAR             # one var, value-less names"
            echo "  printenv NON_SECRET_VAR          # one var, hard-fails if unset"
            echo "  env > /tmp/env-dump              # dump to file (terminal-aware)"
            echo "  declare -p VAR > /tmp/dec        # same"
            ;;
        B5)
            # Reading rendered secret-bearing files via cat-class.
            echo "This file holds rendered secret values. To inspect without leaking:"
            echo "  dotfiles secret list             # registered names + cache status"
            echo "  cat <\$file>.tmpl                 # template (op:// refs, no values)"
            echo "If you really need to peek:"
            echo "  cat <\$file> > /tmp/x             # terminal-aware redirect"
            ;;
        R1)
            # Read tool against a secret-bearing path.
            echo "Read tool would expose secret-bearing file content to the transcript."
            echo "  dotfiles secret list             # registered names + cache status"
            echo "  Read the .tmpl source instead    # template has refs, not values"
            ;;
        B7)
            # Literal credential in command itself.
            echo "Replace the literal credential in the command with a variable:"
            echo "  TOKEN=\$(op read 'op://Vault/Item/field')"
            echo "  cmd --auth \"\$TOKEN\""
            echo "Or use an already-loaded env var:"
            echo "  cmd --auth \"\$CLOUDFLARE_API_TOKEN\""
            echo "Don't paste literal sk-ant-/AKIA-/ops_-style strings into commands."
            ;;
        B8)
            # Interpreter -c/-e reading a secret-bearing env var.
            echo "Either redirect the interpreter's output:"
            echo "  python -c '...' > /tmp/out"
            echo "Or capture in shell first and pass an arg, not env:"
            echo "  TOKEN=\$(op read 'op://...')"
            echo "  python -c \"...\" --token \"\$TOKEN\""
            ;;
        W1 | W2)
            # Edit/Write of a literal credential into a file.
            echo "Don't commit literal credentials to a file. Replace with one of:"
            echo "  - env-var reference: \\\${TOKEN_NAME}        # resolved at runtime"
            echo "  - 1Password ref:     op://Vault/Item/field  # resolved by template"
            echo "  - capture form:      \$(op read 'op://...')  # at deploy time"
            echo "If this is a test fixture, name the file \`tests/secret-guard*.sh\`"
            echo "or \`docs/secret-handling-cheatsheet.md\` for path-exempt write."
            ;;
        *)
            # Generic fallback (shouldn't trigger with v3.5; here for safety).
            echo "Safe forms (any one is enough):"
            echo "  VAR=\$(<call>)              # capture"
            echo "  <call> > /tmp/secret        # redirect"
            echo "  <call> | pbcopy             # clipboard"
            ;;
        esac
        echo
        echo "Mode: $MODE     (set SECRET_GUARD_MODE or ~/.config/secret-guard/mode)"
        echo "Bypass for this one call: append '  # secret-guard: allow'"
        echo "Full pattern doc: docs/secret-handling-cheatsheet.md"
        echo "Dry-run any command: dotfiles secret-guard explain '<cmd>'"
        echo "================================================================"
    } >&2
    case "$MODE" in
    warn-only) exit 0 ;;
    *) exit 2 ;;
    esac
}

bypass_marker() {
    if printf '%s' "$1" | grep -qE 'secret-guard:[[:space:]]*allow'; then
        log_event "BYPASS" "user explicit bypass marker; secret value lands in transcript by user choice"
        return 0
    fi
    return 1
}

# is_safe_secret_call CMD CALL_RE
# Returns 0 (safe) iff every pipeline in CMD that contains the call is
# safe per S-62's terminal-aware rule:
#   - Capture forms ($() and ``) are stripped first; if the call no
#     longer appears, it was fully captured (safe).
#   - For each remaining segment containing the call, the segment is
#     safe iff:
#       (a) any stage in the segment has a stdout redirect (>, >>, &>,
#           &>>) to a path token; OR
#       (b) the last stage of the segment is in the no-echo allowlist
#           (pbcopy / xclip / wl-copy).
# Otherwise the segment is unsafe and the function returns 1.
#
# Implementation notes:
#   - Segment boundaries are ; && || (logical separators), replaced with
#     a sentinel byte so bash word-splitting can iterate them.
#   - The redirect regex requires a non-digit char before `>` so that
#     `2>` (stderr-only redirect) does NOT count as a stdout redirect.
#     `&>` and `1>` count (but `1>` isn't matched by the simple regex;
#     accept the false positive -- bypass marker handles it).
#   - The allowlist check tokenises the last pipeline stage's first
#     word and compares against a fixed list. Keep this list short; if
#     a sink isn't on it, the user must redirect or use the bypass.
is_safe_secret_call() {
    local cmd="$1" call_re="$2"

    # 0. Strip QUOTED-marker heredoc bodies. `<<'EOF'` and `<<"EOF"`
    #    (plus `<<-` indented variants) preserve the body literally
    #    with no shell expansion -- so any call-token sitting inside
    #    the body is documentation/data, not an executable invocation.
    #    Without this strip, a `git commit -m "$(cat <<'EOF' ... EOF)"`
    #    whose message body mentions `secret-cache-read` / `op read` /
    #    `security find-generic-password` would false-positive on
    #    B1 / B2 / B2b / B2c / B2d / B4a / B4c / B8 (which all gate
    #    through this function). The downstream `$()` / backtick / `<()`
    #    strip on line ~278 also fails when the heredoc body contains
    #    parens (e.g. a conventional-commit subject `feat(scope): ...`),
    #    which is the actual user-visible regression that motivated
    #    this step. UNQUOTED markers (`<<EOF`, `<<-EOF`) keep variable
    #    expansion live and are intentionally NOT stripped here -- rule
    #    B6 inspects them for secret-name derefs.
    cmd=$(printf '%s' "$cmd" | awk '
    BEGIN { in_hd = 0; marker = ""; dash_flag = 0 }
    {
        if (in_hd) {
            check = $0
            if (dash_flag) sub(/^[[:space:]]+/, "", check)
            if (check == marker) in_hd = 0
            next
        }
        if (match($0, /<<-?[\047"][A-Za-z_][A-Za-z0-9_]*[\047"]/)) {
            tok = substr($0, RSTART, RLENGTH)
            dash_flag = (substr(tok, 3, 1) == "-")
            mtok = tok
            sub(/^<</, "", mtok)
            sub(/^-/, "", mtok)
            sub(/^[\047"]/, "", mtok)
            sub(/[\047"]$/, "", mtok)
            marker = mtok
            in_hd = 1
        }
        print
    }')

    # 1. Strip capture / no-stdout-leak constructs. Single-level only;
    #    deeply nested forms fall through to the segment check below.
    #      `$(...)`  -- command substitution: stdout captured into
    #                   the surrounding string, never reaches terminal.
    #      `\`...\`` -- backtick capture, same semantics.
    #      `<(...)`  -- process substitution feeding stdin via
    #                   /dev/fd/N. The substituted command's stdout
    #                   does NOT reach the calling shell's stdout;
    #                   it goes to a fifo/fd that the consuming
    #                   command reads. Safe in the same sense as
    #                   `$(...)` for our threat model. Lets
    #                   `curl -H @<(op read 'op://...')` work without
    #                   the bypass marker.
    local stripped="$cmd"
    while [[ "$stripped" =~ \$\([^\(\)]*\) ]]; do
        stripped="${stripped/"${BASH_REMATCH[0]}"/}"
    done
    while [[ "$stripped" =~ \`[^\`]*\` ]]; do
        stripped="${stripped/"${BASH_REMATCH[0]}"/}"
    done
    while [[ "$stripped" =~ \<\([^\(\)]*\) ]]; do
        stripped="${stripped/"${BASH_REMATCH[0]}"/}"
    done

    # Fast path: if the call doesn't appear after stripping, it was
    # fully captured.
    if ! printf '%s' "$stripped" | grep -qE "(^|[^a-zA-Z_/-])(${call_re})"; then
        return 0
    fi

    # 2. Quote-aware segment splitting: replace `;` `&&` `||` with a
    #    sentinel ONLY when they appear OUTSIDE single/double quotes.
    #    This matters for commands like
    #      python -c "import os; print(os.environ['X'])" > /tmp/out
    #    where the `;` is inside the python script body, not a logical
    #    statement separator. A naive split would put `> /tmp/out` in
    #    a different segment from the call and falsely block the
    #    redirect-anywhere safe form.
    local sep=$'\034'
    local marked
    marked=$(printf '%s' "$stripped" | awk -v sep="$sep" '
    { buf = buf (NR > 1 ? "\n" : "") $0 }
    END {
        in_s = 0; in_d = 0
        out = ""; i = 1; n = length(buf)
        while (i <= n) {
            c = substr(buf, i, 1)
            c2 = substr(buf, i, 2)
            if (in_s) {
                if (c == "\047") in_s = 0
                out = out c; i++
            } else if (in_d) {
                if (c == "\\" && i < n) {
                    out = out c substr(buf, i+1, 1); i += 2; continue
                }
                if (c == "\"") in_d = 0
                out = out c; i++
            } else {
                if (c == "\047") { in_s = 1; out = out c; i++ }
                else if (c == "\"") { in_d = 1; out = out c; i++ }
                else if (c2 == "&&" || c2 == "||") { out = out sep; i += 2 }
                else if (c == ";") { out = out sep; i++ }
                else { out = out c; i++ }
            }
        }
        printf "%s", out
    }')

    # 3. Iterate segments. Each one containing the call must be safe.
    local seg first last
    local IFS="$sep"
    # shellcheck disable=SC2206  # intentional word split on sentinel
    local -a segments=( $marked )
    unset IFS

    for seg in "${segments[@]}"; do
        printf '%s' "$seg" | grep -qE "(^|[^a-zA-Z_/-])(${call_re})" || continue

        # Safe form (a): stdout redirect anywhere in the segment.
        # Pattern: a `>` or `>>` not preceded by a digit, followed by
        # whitespace + a non-special char (path or /dev/null etc.).
        if printf '%s' "$seg" | grep -qE '(^|[^0-9])>>?[[:space:]]*[^[:space:]&|>]'; then
            continue
        fi

        # Safe form (b): last pipeline stage's first word is in the
        # no-echo allowlist.
        last="${seg##*|}"
        # Trim leading whitespace.
        last="${last#"${last%%[![:space:]]*}"}"
        first="${last%%[[:space:]]*}"
        case "$first" in
            pbcopy | xclip | wl-copy) continue ;;
        esac

        return 1
    done

    return 0
}

# split_quote_aware SEP
# Read CMD on stdin, write to stdout with `;`, `&&`, `||` (when OUTSIDE
# single/double quotes) replaced by SEP. Lets callers split a command
# into logical segments without breaking on `;`/`&&` inside quoted
# strings (e.g. `python -c "import os; print(os.environ['X'])" > /tmp/x`
# keeps the redirect attached to the python call, not separated).
split_quote_aware() {
    awk -v sep="$1" '
    { buf = buf (NR > 1 ? "\n" : "") $0 }
    END {
        in_s = 0; in_d = 0
        out = ""; i = 1; n = length(buf)
        while (i <= n) {
            c = substr(buf, i, 1)
            c2 = substr(buf, i, 2)
            if (in_s) {
                if (c == "\047") in_s = 0
                out = out c; i++
            } else if (in_d) {
                if (c == "\\" && i < n) {
                    out = out c substr(buf, i+1, 1); i += 2; continue
                }
                if (c == "\"") in_d = 0
                out = out c; i++
            } else {
                if (c == "\047") { in_s = 1; out = out c; i++ }
                else if (c == "\"") { in_d = 1; out = out c; i++ }
                else if (c2 == "&&" || c2 == "||") { out = out sep; i += 2 }
                else if (c == ";") { out = out sep; i++ }
                else { out = out c; i++ }
            }
        }
        printf "%s", out
    }'
}

# extract_unquoted_heredoc_bodies
# Read CMD on stdin, emit ONLY the body lines of heredocs whose marker
# is UNQUOTED (`<<EOF`, `<<-EOF`). Quoted-marker bodies (`<<'EOF'`,
# `<<"EOF"`) preserve the body literally with no shell expansion, so
# any $VAR in their bodies is not a leak vector and we skip them. Used
# by B6 to check whether a secret-bearing variable is actually
# expanded into a heredoc body, rather than the prior flat-grep that
# fired on any unquoted heredoc + any secret-deref anywhere in CMD.
extract_unquoted_heredoc_bodies() {
    awk '
    BEGIN { in_hd = 0; marker = ""; dash_flag = 0; quoted = 0 }
    {
        if (in_hd) {
            check = $0
            if (dash_flag) sub(/^[[:space:]]+/, "", check)
            if (check == marker) { in_hd = 0; next }
            if (!quoted) print
            next
        }
        if (match($0, /<<-?[\047"]?[A-Za-z_][A-Za-z0-9_]*[\047"]?/)) {
            tok = substr($0, RSTART, RLENGTH)
            dash_flag = (substr(tok, 3, 1) == "-")
            mtok = tok
            sub(/^<</, "", mtok)
            sub(/^-/, "", mtok)
            quoted = (mtok ~ /^[\047"]/)
            sub(/^[\047"]/, "", mtok)
            sub(/[\047"]$/, "", mtok)
            marker = mtok
            in_hd = 1
        }
    }'
}

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')

# Variable names (no $ prefix) we treat as secret-bearing.
SECRET_NAME_RE='\b(CLOUDFLARE_API_TOKEN|R2_SECRET_ACCESS_KEY|OP_SERVICE_ACCOUNT_TOKEN|OP_SESSION_[A-Z0-9_]+|[A-Z][A-Z0-9_]*_(TOKEN|SECRET|PASSWORD|PASSPHRASE|API_KEY|PRIVATE_KEY))\b'
# Variable dereferences ($X or ${X}) of the same.
SECRET_DEREF_RE='\$\{?'"$SECRET_NAME_RE"

# Files whose content is a resolved secret on a configured machine.
# Terminator class deliberately excludes `.` so `.netrc.tmpl`, `.aws/
# credentials.tmpl` and other template-with-op-refs do NOT match the
# secret-file pattern. Word boundary `\b` matched `.` (word/non-word
# transition) and caused a class of false positives; switching to an
# explicit separator class fixes that AND keeps the SSH-key behavior
# (`id_ed25519.pub` non-match) uniform across all path entries.
#
# Bare `.pem` deliberately NOT included. The format is used for both
# private keys and public certs; without a path heuristic we'd flag
# every `/etc/ssl/certs/*.pem` read. Canonical private-key directories
# (`/etc/ssl/private/`, `/etc/pki/tls/private/`) are explicitly listed
# so a `.pem` under them still blocks. Other private keys land in
# `~/.ssh/id_*` (caught) or under user-managed paths (bypass marker if
# you really need to cat them). `.p12` and `.pfx` are almost always
# private and stay.
SEPCLASS='([[:space:]]|;|&|\||>|<|$)'
SECRET_FILES_BASH_RE="/conf\.d/secrets\.fish${SEPCLASS}|/\.netrc${SEPCLASS}|/\.aws/credentials${SEPCLASS}|/\.config/op/[^[:space:]]+|\.local/[^[:space:]]*\.(env|secrets|tokens)${SEPCLASS}|/\.ssh/id_[a-zA-Z0-9_-]+${SEPCLASS}|/\.kube/config${SEPCLASS}|/\.docker/config\.json${SEPCLASS}|/\.npmrc${SEPCLASS}|/\.pypirc${SEPCLASS}|/\.cargo/credentials${SEPCLASS}|/\.gem/credentials${SEPCLASS}|/\.git-credentials${SEPCLASS}|/\.config/gh/hosts\.yml${SEPCLASS}|/\.config/gcloud/application_default_credentials\.json${SEPCLASS}|/etc/ssl/private/[^[:space:]]+|/etc/pki/tls/private/[^[:space:]]+|\.(p12|pfx)${SEPCLASS}"

case "$TOOL" in
Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
    [ -z "$CMD" ] && exit 0
    bypass_marker "$CMD" && exit 0

    # 1. 1Password CLI verbs that print a secret value to stdout.
    #    Covers `op read`, `op item get` (any flag, including --reveal /
    #    --field), `op signin --raw` (prints session token), `op connect
    #    token create` (prints connect token), `op service-account
    #    create` (prints SA token). All share the terminal-aware
    #    safe-form rule.
    OP_SECRET_VERBS_RE='op[[:space:]]+(read|item[[:space:]]+get|signin[[:space:]]+(--raw|-r)|connect[[:space:]]+token[[:space:]]+create|service-account[[:space:]]+create)'
    if printf '%s' "$CMD" | grep -qE "(^|[^a-zA-Z_/-])${OP_SECRET_VERBS_RE}"; then
        if ! is_safe_secret_call "$CMD" "$OP_SECRET_VERBS_RE"; then
            block "1Password CLI output would land in the transcript." "B1"
        fi
    fi

    # 2. `secret-cache-read NAME` -- same terminal-aware rule.
    if printf '%s' "$CMD" | grep -qE '(^|[^a-zA-Z_/-])secret-cache-read[[:space:]]'; then
        if ! is_safe_secret_call "$CMD" 'secret-cache-read'; then
            block "'secret-cache-read' output would land in the transcript." "B2"
        fi
    fi

    # 2b. macOS Keychain raw read. `security find-generic-password -w`
    #     (or `-ws SVC`) prints the password to stdout; same threat as
    #     `op read` and `secret-cache-read`. The single-letter flag is
    #     either standalone (`-w`) or paired with `-s` as `-ws`.
    if printf '%s' "$CMD" | grep -qE '(^|[^a-zA-Z_/-])security[[:space:]]+find-generic-password[[:space:]][^|]*-w(s|[[:space:]]|$)'; then
        if ! is_safe_secret_call "$CMD" 'security[[:space:]]+find-generic-password'; then
            block "'security find-generic-password -w/-ws' would print the keychain password to the transcript." "B2b"
        fi
    fi

    # 2c. `gh auth token` prints the GitHub CLI's stored token.
    if printf '%s' "$CMD" | grep -qE '(^|[^a-zA-Z_/-])gh[[:space:]]+auth[[:space:]]+token([[:space:]]|$)'; then
        if ! is_safe_secret_call "$CMD" 'gh[[:space:]]+auth[[:space:]]+token'; then
            block "'gh auth token' would print the GitHub CLI token to the transcript." "B2c"
        fi
    fi

    # 2d. Decryption commands. `gpg --decrypt|-d`, `openssl enc -d`,
    #     `openssl rsautl -decrypt`, `openssl pkeyutl -decrypt` all
    #     write plaintext to stdout. Treat plaintext as secret by
    #     default; same terminal-aware rule applies.
    #
    #     Each flag carries a terminator (whitespace or end-of-string)
    #     so that:
    #       gpg --decrypt-files foo.gpg   # writes to .out, NOT stdout
    #       openssl enc -des-cbc ...      # encrypting WITH des cipher
    #     do not substring-match on `--decrypt` / `-d`. `-d` in openssl
    #     enc is further required to be preceded by whitespace so it
    #     anchors to an actual flag boundary, not a substring of
    #     `-aes-128-cbc` style cipher names.
    DECRYPT_RE='gpg[[:space:]]+(-d([[:space:]]|$)|--decrypt([[:space:]]|$))|openssl[[:space:]]+(enc[[:space:]]+([^|]*[[:space:]])?-d([[:space:]]|$)|rsautl[[:space:]]+([^|]*[[:space:]])?-decrypt([[:space:]]|$)|pkeyutl[[:space:]]+([^|]*[[:space:]])?-decrypt([[:space:]]|$))'
    if printf '%s' "$CMD" | grep -qE "(^|[^a-zA-Z_/-])${DECRYPT_RE}"; then
        if ! is_safe_secret_call "$CMD" "$DECRYPT_RE"; then
            block "decryption command would write plaintext to the transcript." "B2d"
        fi
    fi

    # 3. echo|printf|print that emits a secret-named var to stdout.
    #    Capture-form-aware: $() and `` captures are stripped FIRST
    #    (their stdout is captured into the surrounding string and
    #    never reaches the terminal), and quoted-marker heredoc bodies
    #    are stripped too (literal, no expansion). Then segment-aware:
    #    split on `;`/`&&`/`||` (quote-aware) and check each segment
    #    in isolation. Previously the regex used `[^|]*` to span from
    #    the print-verb to the secret-deref, which matched across `&&`
    #    boundaries and on print-verbs inside `$(...)` captures.
    #
    #    Still NOT terminal-aware for redirect (`echo $TOKEN > file`
    #    blocks even though no transcript leak), per the original
    #    design intent: an echo of $TOKEN is suspicious enough to flag
    #    regardless of sink. The bypass marker is the escape hatch.
    b3_stripped=$(printf '%s' "$CMD" | awk '
    BEGIN { in_hd = 0; marker = ""; dash_flag = 0 }
    {
        if (in_hd) {
            check = $0
            if (dash_flag) sub(/^[[:space:]]+/, "", check)
            if (check == marker) in_hd = 0
            next
        }
        if (match($0, /<<-?[\047"][A-Za-z_][A-Za-z0-9_]*[\047"]/)) {
            tok = substr($0, RSTART, RLENGTH)
            dash_flag = (substr(tok, 3, 1) == "-")
            mtok = tok
            sub(/^<</, "", mtok)
            sub(/^-/, "", mtok)
            sub(/^[\047"]/, "", mtok)
            sub(/[\047"]$/, "", mtok)
            marker = mtok
            in_hd = 1
        }
        print
    }')
    while [[ "$b3_stripped" =~ \$\([^\(\)]*\) ]]; do
        b3_stripped="${b3_stripped/"${BASH_REMATCH[0]}"/}"
    done
    while [[ "$b3_stripped" =~ \`[^\`]*\` ]]; do
        b3_stripped="${b3_stripped/"${BASH_REMATCH[0]}"/}"
    done
    b3_sep=$'\034'
    b3_marked=$(printf '%s' "$b3_stripped" | split_quote_aware "$b3_sep")
    b3_unsafe=0
    b3_oldifs="$IFS"
    IFS="$b3_sep"
    # shellcheck disable=SC2206  # intentional word split on sentinel
    b3_segments=( $b3_marked )
    IFS="$b3_oldifs"
    for b3_seg in "${b3_segments[@]}"; do
        if printf '%s' "$b3_seg" | grep -qE "(^|[^a-zA-Z_/-])(echo|printf|print)[[:space:]][^|]*${SECRET_DEREF_RE}"; then
            b3_unsafe=1
            break
        fi
    done
    if [ "$b3_unsafe" = "1" ]; then
        block "command would print a secret-bearing variable to stdout" "B3"
    fi
    if printf '%s' "$CMD" | grep -qE "<<<[[:space:]]*[\"']?[^\"']*${SECRET_DEREF_RE}"; then
        block "here-string would expose a secret-bearing variable" "B3.5"
    fi

    # 4a. Bare `env`/`printenv`/`set` (no args) -> dumps every var
    #     including secret-bearing ones. Terminator class deliberately
    #     excludes `-` and alphanumerics so wrappers (`env -u FOO bar`,
    #     `env A=B cmd`, `set -e`, `set -x`, `set -- "$@"`, `set +H`)
    #     stay allowed. Terminal-aware: `set > file`, `env | pbcopy`
    #     are safe.
    ENV_DUMP_BARE_RE='(env|printenv|set)([[:space:]]*$|[[:space:]]*[;&|]|[[:space:]]*>)'
    if printf '%s' "$CMD" | grep -qE "(^|[;&|][[:space:]]*|[[:space:]])${ENV_DUMP_BARE_RE}"; then
        if ! is_safe_secret_call "$CMD" "$ENV_DUMP_BARE_RE"; then
            block "unfiltered 'env'/'printenv'/'set' would dump every credential in the environment" "B4a"
        fi
    fi

    # 4b. `printenv NAME` of a secret-bearing variable.
    if printf '%s' "$CMD" | grep -qE "(^|[^a-zA-Z_/-])printenv[[:space:]]+${SECRET_NAME_RE}"; then
        block "'printenv' of a secret-bearing variable would print its value" "B4b"
    fi

    # 4c. `declare -p [VAR]`, `typeset -p [VAR]`, `export -p` print
    #     variable definitions including resolved values. Same
    #     terminal-aware rule as 4a.
    DECLARE_P_RE='(declare|typeset|export)[[:space:]]+-p'
    if printf '%s' "$CMD" | grep -qE "(^|[^a-zA-Z_/-])${DECLARE_P_RE}"; then
        if ! is_safe_secret_call "$CMD" "$DECLARE_P_RE"; then
            block "'declare/typeset/export -p' would print variable definitions including resolved secret values" "B4c"
        fi
    fi

    # 5. Reading rendered secret-bearing files via cat-class viewers.
    #    Segment-aware so that
    #      cat /tmp/safe.txt && less ~/.aws/credentials
    #    doesn't false-fire (the cat is in one segment, the secret-path
    #    in another); the prior `[^|]*` regex spanned across `&&`
    #    boundaries from the cat-verb to a downstream path. Same shape
    #    of bug as the original B3 / B6.
    b5_sep=$'\034'
    b5_marked=$(printf '%s' "$CMD" | split_quote_aware "$b5_sep")
    b5_unsafe=0
    b5_oldifs="$IFS"
    IFS="$b5_sep"
    # shellcheck disable=SC2206  # intentional word split on sentinel
    b5_segments=( $b5_marked )
    IFS="$b5_oldifs"
    for b5_seg in "${b5_segments[@]}"; do
        if printf '%s' "$b5_seg" | grep -qE "(^|[^a-zA-Z_/-])(cat|bat|head|tail|less|more|xxd|hexdump)[[:space:]][^|]*(${SECRET_FILES_BASH_RE})"; then
            b5_unsafe=1
            break
        fi
    done
    if [ "$b5_unsafe" = "1" ]; then
        block "command would print a known secret-bearing file" "B5"
    fi

    # 6. Heredoc body that expands a secret-named variable. Heredocs
    #    with an UNQUOTED marker perform variable expansion (`<<EOF`,
    #    `<<-EOF`); markers wrapped in single or double quotes
    #    (`<<'EOF'`, `<<"EOF"`) preserve the body literally and are
    #    skipped. Extract ONLY the unquoted-marker bodies via the awk
    #    helper, then grep that extract for SECRET_DEREF_RE. Prior
    #    impl flat-grep'd both predicates against the whole CMD, which
    #    false-fired on the common pattern
    #      cat > /tmp/x <<JSON ... no-secrets ... JSON
    #      curl -H "Bearer $CF_API_TOKEN" ... --data @/tmp/x
    #    where the safe `-H` curl is outside any heredoc.
    #    (Rule B3 already catches the here-string `<<<`.)
    HEREDOC_BODIES=$(printf '%s' "$CMD" | extract_unquoted_heredoc_bodies)
    if [ -n "$HEREDOC_BODIES" ] && \
        printf '%s' "$HEREDOC_BODIES" | grep -qE "${SECRET_DEREF_RE}"; then
        block "heredoc with unquoted marker would expand a secret-bearing variable into its body" "B6"
    fi

    # 7. Literal credential value embedded in the command itself. The
    #    Bash tool_input.command is captured into the JSONL transcript
    #    verbatim, so a command like
    #      httpie POST ... Authorization:"Bearer sk-ant-..."
    #    leaks the secret even though no rule above fires. Scan the
    #    command against the same shared pattern set used for Edit/
    #    Write content (claude-guardrails' patterns/secrets.json).
    PATTERNS="${HOME}/.claude/hooks/patterns/secrets.json"
    if [ -f "$PATTERNS" ]; then
        HIT=$(jq -rn --arg p "$CMD" --slurpfile pats "$PATTERNS" '
          $pats[0] | map(select(.r as $r | $p | test($r))) | map(.n) | .[0] // empty
        ' 2>/dev/null)
        if [ -n "$HIT" ]; then
            block "command contains a literal credential ($HIT); the command string is captured in the transcript verbatim" "B7"
        fi
    fi

    # 8. Interpreter `-c` / `-e` script that reads a secret-bearing
    #    env var. Languages vary (Python `os.environ['X']`, Node
    #    `process.env.X`, Ruby `ENV['X']`, Perl `$ENV{X}`); the rule
    #    fires only when ALL three signals are present in the command:
    #    (a) interpreter -c/-e form,
    #    (b) recognisable env-access syntax,
    #    (c) a secret-bearing variable name.
    #    Same terminal-aware safe-form check applies, so
    #    `python -c "print(os.environ['X'])" > /tmp/out` is allowed.
    INTERPRETER_RE='(python[23]?|node|deno|ruby|perl)[[:space:]]+(-c|-e)[[:space:]]'
    INTERPRETER_ENV_ACCESS_RE='(os\.environ|process\.env|ENV\[|\$ENV\{)'
    # Three signals must coexist IN THE SAME SEGMENT, not just somewhere
    # in CMD. Prior flat-grep aggregation false-fired on
    #   python3 -c "import os; print(os.environ['HOME'])" \
    #     && curl -H "Bearer $CLOUDFLARE_API_TOKEN" ...
    # where the interpreter is in segment 1 (reads HOME, not a secret)
    # and the secret-name is in segment 2 (inside a safe-pattern curl).
    b8_sep=$'\034'
    b8_marked=$(printf '%s' "$CMD" | split_quote_aware "$b8_sep")
    b8_unsafe=0
    b8_oldifs="$IFS"
    IFS="$b8_sep"
    # shellcheck disable=SC2206  # intentional word split on sentinel
    b8_segments=( $b8_marked )
    IFS="$b8_oldifs"
    for b8_seg in "${b8_segments[@]}"; do
        if printf '%s' "$b8_seg" | grep -qE "(^|[^a-zA-Z_/-])${INTERPRETER_RE}" \
            && printf '%s' "$b8_seg" | grep -qE "$INTERPRETER_ENV_ACCESS_RE" \
            && printf '%s' "$b8_seg" | grep -qE "$SECRET_NAME_RE"; then
            if ! is_safe_secret_call "$b8_seg" "$INTERPRETER_RE"; then
                b8_unsafe=1
                break
            fi
        fi
    done
    if [ "$b8_unsafe" = "1" ]; then
        block "interpreter -c/-e script reads a secret-bearing env var; its output would land in the transcript" "B8"
    fi
    ;;

Read)
    P=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
    [ -z "$P" ] && exit 0
    # Order matters: SSH public keys (*.pub) are matched FIRST as an
    # explicit allow, so the broader id_* glob below doesn't catch
    # them. `*-cert.pub` is a subset of `*.pub` and needs no extra
    # case (covered by the first arm).
    #
    # Bare `*.pem` NOT listed (covers both private keys and public
    # certs; the public-cert case `/etc/ssl/certs/*.pem` was a regular
    # false positive). Canonical private-key dirs `/etc/ssl/private/`
    # and `/etc/pki/tls/private/` are listed explicitly so reads under
    # them still block. True SSH private keys are caught by
    # `*/.ssh/id_*`. `*.p12` / `*.pfx` are kept (almost always private).
    case "$P" in
    */.ssh/*.pub) ;;
    */conf.d/secrets.fish \
        | */.netrc \
        | */.aws/credentials \
        | */.config/op/* \
        | *.env | *.secrets | *.tokens \
        | */.ssh/id_* \
        | */.kube/config \
        | */.docker/config.json \
        | */.npmrc | */.pypirc \
        | */.cargo/credentials | */.gem/credentials \
        | */.git-credentials \
        | */.config/gh/hosts.yml \
        | */.config/gcloud/application_default_credentials.json \
        | */etc/ssl/private/* | */etc/pki/tls/private/* \
        | *.p12 | *.pfx)
        block "Read tool target is a known secret-bearing path: $P" "R1"
        ;;
    esac
    ;;

Edit | Write | MultiEdit)
    # Path-based exemption for test fixtures. The secret-guard test
    # runner contains pattern-matching example credentials so that
    # the test cases exercise the W1 / B7 rules. Without this
    # exemption the hook blocks edits to its own test file once
    # deployed. Add similar paths here if you create more fixture
    # files. Bypass marker is the alternative for ad-hoc cases.
    EDIT_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
    case "$EDIT_PATH" in
    */tests/secret-guard.sh | */tests/secret-guard*.sh | */docs/secret-handling-cheatsheet.md)
        log_event "BYPASS" "test/doc fixture path exemption: $EDIT_PATH"
        exit 0
        ;;
    esac

    # Both new_string and old_string are echoed back in the tool's
    # diff output, which lands in the transcript. Scan both, plus
    # Write's `content` and MultiEdit's `edits[].{new,old}_string`.
    PAYLOAD=$(printf '%s' "$INPUT" | jq -r '
      [
        (.tool_input.new_string // ""),
        (.tool_input.old_string // ""),
        (.tool_input.content // ""),
        ((.tool_input.edits // []) | map((.new_string // "") + "\n" + (.old_string // "")) | join("\n"))
      ] | join("\n")
    ')
    [ -z "$PAYLOAD" ] && exit 0
    bypass_marker "$PAYLOAD" && exit 0
    PATTERNS="${HOME}/.claude/hooks/patterns/secrets.json"
    if [ -f "$PATTERNS" ]; then
        HIT=$(jq -rn --arg p "$PAYLOAD" --slurpfile pats "$PATTERNS" '
          $pats[0] | map(select(.r as $r | $p | test($r))) | map(.n) | .[0] // empty
        ' 2>/dev/null)
        if [ -n "$HIT" ]; then
            block "Edit/Write would commit a literal secret to a file ($HIT)" "W1"
        fi
    fi
    ;;
esac

exit 0
