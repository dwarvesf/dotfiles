#!/usr/bin/env bash
# tests/secret-guard.sh -- spec test matrix for S-62.
#
# Runs the secret-guard hook script against every numbered case in
# docs/specs/S-62-secret-guard-pretooluse-hook.md and reports
# pass/fail. Exits 0 if every test matched its expected exit code,
# 1 otherwise.
#
# Usage:
#   bash tests/secret-guard.sh                 # all tests
#   bash tests/secret-guard.sh --verbose       # also print stderr on PASS
#   HOOK=/path/to/secret-guard.sh bash tests/secret-guard.sh
#
# This runner is self-contained: no bats, no test framework. Each
# case is a one-liner with a label, an expected exit code, and a JSON
# payload piped to the hook on stdin. Keep it that way.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${HOOK:-$REPO_ROOT/home/dot_claude/hooks/secret-guard/executable_secret-guard.sh}"
VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

if [ ! -x "$HOOK" ] && [ ! -r "$HOOK" ]; then
    echo "ERROR: hook not found at $HOOK" >&2
    exit 1
fi

# Fixture credentials. Defined as runtime concatenations so the SOURCE
# FILE does NOT contain literal pattern matches that
# claude-guardrails' scan-commit hook would catch on every commit
# (the runtime values still match the regexes the test exercises).
# To keep this trick working, never refactor these into single string
# literals.
FAKE_SK_ANT="sk-ant-""api03-""XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
FAKE_AKIA="AKIA""IOSFODNN7EXAMPLE"

PASS_COUNT=0
FAIL_COUNT=0
FAILED_LABELS=()

run() {
    local label="$1" expect="$2" json="$3"
    local out rc
    out=$(printf '%s' "$json" | bash "$HOOK" 2>&1)
    rc=$?
    if [ "$rc" -eq "$expect" ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        if [ "$VERBOSE" -eq 1 ]; then
            printf 'PASS  rc=%s  %s\n' "$rc" "$label"
        else
            printf 'PASS  rc=%s  %s\n' "$rc" "$label"
        fi
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_LABELS+=("$label")
        printf 'FAIL  rc=%s want=%s  %s\n' "$rc" "$expect" "$label"
        printf '%s\n' "$out" | head -5 | sed 's/^/        /'
    fi
}

# ---------------------------------------------------------------
# Section 1: should BLOCK (rc=2). Numbered to match S-62 spec.
# ---------------------------------------------------------------
section() { printf '\n--- %s ---\n' "$*"; }

section "1. BLOCK -- Bash op read variants"
run "01 bare op read"                              2 '{"tool_name":"Bash","tool_input":{"command":"op read op://Toolkit/cf-api-token/credential"}}'
run "02 op read | paste-token (USER REPRO)"        2 '{"tool_name":"Bash","tool_input":{"command":"op read op://Personal/opencode-go/credential | paste-token"}}'
run "03 op read | tee (no final redirect)"         2 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z | tee /tmp/x"}}'
run "04 op read | jq (no redirect)"                2 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z | jq -r ."}}'
run "05 op read | grep ."                          2 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z | grep ."}}'
run "06 op read | bash"                            2 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z | bash"}}'
run "07 op read | xargs"                           2 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z | xargs -I{} echo {}"}}'
run "08 op read 2>&1 | grep"                       2 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z 2>&1 | grep ."}}'
run "09 op read 2> err but stdout open"            2 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z 2> /tmp/err"}}'

section "2. BLOCK -- secret-cache-read variants"
run "10 bare secret-cache-read"                    2 '{"tool_name":"Bash","tool_input":{"command":"secret-cache-read CLOUDFLARE_API_TOKEN"}}'
run "11 secret-cache-read | tee"                   2 '{"tool_name":"Bash","tool_input":{"command":"secret-cache-read FOO | tee /tmp/x"}}'

section "3. BLOCK -- echo/printf/heredoc of secret-named var"
run "12 echo \$CLOUDFLARE_API_TOKEN"               2 '{"tool_name":"Bash","tool_input":{"command":"echo $CLOUDFLARE_API_TOKEN"}}'
run "13 printf with \${MY_API_KEY}"                2 '{"tool_name":"Bash","tool_input":{"command":"printf \"key=%s\" \"${MY_API_KEY}\""}}'
run "14 here-string of \$OP_SERVICE_ACCOUNT_TOKEN" 2 '{"tool_name":"Bash","tool_input":{"command":"cat <<<\"$OP_SERVICE_ACCOUNT_TOKEN\""}}'

section "4. BLOCK -- env / printenv"
run "15 bare env"                                  2 '{"tool_name":"Bash","tool_input":{"command":"env"}}'
run "16 bare printenv"                             2 '{"tool_name":"Bash","tool_input":{"command":"printenv"}}'
run "17 printenv OP_SERVICE_ACCOUNT_TOKEN"         2 '{"tool_name":"Bash","tool_input":{"command":"printenv OP_SERVICE_ACCOUNT_TOKEN"}}'

section "5. BLOCK -- cat-class on secret-bearing files"
run "18 cat secrets.fish"                          2 '{"tool_name":"Bash","tool_input":{"command":"cat ~/.config/fish/conf.d/secrets.fish"}}'
run "19 head .netrc"                               2 '{"tool_name":"Bash","tool_input":{"command":"head ~/.netrc"}}'
run "20 less .aws/credentials"                     2 '{"tool_name":"Bash","tool_input":{"command":"less ~/.aws/credentials"}}'

section "6. BLOCK -- Read tool"
run "21 Read secrets.fish"                         2 '{"tool_name":"Read","tool_input":{"file_path":"/Users/tieubao/.config/fish/conf.d/secrets.fish"}}'
run "22 Read .netrc"                               2 '{"tool_name":"Read","tool_input":{"file_path":"/Users/tieubao/.netrc"}}'
run "23 Read .aws/credentials"                     2 '{"tool_name":"Read","tool_input":{"file_path":"/Users/tieubao/.aws/credentials"}}'

section "7. BLOCK -- Edit/Write/MultiEdit literal credentials"
run "24 Write sk-ant key"                          2 '{"tool_name":"Write","tool_input":{"content":"export ANTHROPIC='"$FAKE_SK_ANT"'"}}'
run "25 Write AKIA key"                            2 '{"tool_name":"Write","tool_input":{"content":"aws_access_key_id='"$FAKE_AKIA"'"}}'

section "7b. BLOCK -- audit-pass extensions (FN1 / FN2 / FN3)"
# FN1: literal credential pasted into the Bash command string itself.
run "53 Bash literal sk-ant in command (FN1)"      2 '{"tool_name":"Bash","tool_input":{"command":"http POST https://api.example.com/auth Authorization:\"Bearer '"$FAKE_SK_ANT"'\""}}'
run "54 Bash literal AKIA in command (FN1)"        2 '{"tool_name":"Bash","tool_input":{"command":"aws s3 ls --access-key-id '"$FAKE_AKIA"'"}}'
# FN2: heredoc with unquoted marker that expands a secret-named var.
run "55 heredoc <<EOF expands \$TOKEN (FN2)"        2 '{"tool_name":"Bash","tool_input":{"command":"cat <<EOF\n$CLOUDFLARE_API_TOKEN\nEOF"}}'
# FN3: Edit old_string carries a literal secret into the tool diff.
run "57 Edit old_string with literal sk-ant (FN3)" 2 '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x","old_string":"export ANTHROPIC='"$FAKE_SK_ANT"'","new_string":"export ANTHROPIC=replaced"}}'

section "7c. BLOCK -- ultrathink-pass Tier 1 (op alternates / keychain / SSH)"
# T1.1: SSH private keys via cat / Read.
run "60 cat ~/.ssh/id_ed25519 (T1.1)"              2 '{"tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_ed25519"}}'
run "61 Read ~/.ssh/id_ed25519 (T1.1)"             2 '{"tool_name":"Read","tool_input":{"file_path":"/Users/tieubao/.ssh/id_ed25519"}}'
# T1.2: alternate op verbs.
run "62 op item get --reveal (T1.2)"               2 '{"tool_name":"Bash","tool_input":{"command":"op item get \"My Item\" --field credential --reveal"}}'
run "63 op signin --raw (T1.2)"                    2 '{"tool_name":"Bash","tool_input":{"command":"op signin --raw"}}'
# T1.3: macOS Keychain raw read.
run "64 security find-generic-password -ws (T1.3)" 2 '{"tool_name":"Bash","tool_input":{"command":"security find-generic-password -ws SVC -a $USER"}}'
run "65 security ... -w bare (T1.3)"               2 '{"tool_name":"Bash","tool_input":{"command":"security find-generic-password -s SVC -a $USER -w"}}'

section "7d. BLOCK -- ultrathink-pass Tier 2 (env-dump / gh / decrypt / interpreter)"
# T2.1: more credential file paths.
run "66 cat ~/.kube/config (T2.1)"                 2 '{"tool_name":"Bash","tool_input":{"command":"cat ~/.kube/config"}}'
run "67 Read ~/.docker/config.json (T2.1)"         2 '{"tool_name":"Read","tool_input":{"file_path":"/Users/tieubao/.docker/config.json"}}'
run "68 Read ~/.npmrc (T2.1)"                      2 '{"tool_name":"Read","tool_input":{"file_path":"/Users/tieubao/.npmrc"}}'
run "69 Read /etc/ssl/private/server.pem (T2.1)"   2 '{"tool_name":"Read","tool_input":{"file_path":"/etc/ssl/private/server.pem"}}'
# T2.2: env-dump variants beyond env/printenv.
run "70 bare set (T2.2)"                           2 '{"tool_name":"Bash","tool_input":{"command":"set"}}'
run "71 declare -p OP_SERVICE_ACCOUNT_TOKEN (T2.2)" 2 '{"tool_name":"Bash","tool_input":{"command":"declare -p OP_SERVICE_ACCOUNT_TOKEN"}}'
run "72 export -p (T2.2)"                          2 '{"tool_name":"Bash","tool_input":{"command":"export -p"}}'
run "73 typeset -p CLOUDFLARE_API_TOKEN (T2.2)"    2 '{"tool_name":"Bash","tool_input":{"command":"typeset -p CLOUDFLARE_API_TOKEN"}}'
# T2.3: gh auth token.
run "74 gh auth token (T2.3)"                      2 '{"tool_name":"Bash","tool_input":{"command":"gh auth token"}}'
# T2.5: decryption commands.
run "75 gpg --decrypt (T2.5)"                      2 '{"tool_name":"Bash","tool_input":{"command":"gpg --decrypt secret.gpg"}}'
run "76 openssl enc -d (T2.5)"                     2 '{"tool_name":"Bash","tool_input":{"command":"openssl enc -d -aes-256-cbc -in secret.enc -k password"}}'
# T2.4: interpreter -c/-e env-print.
run "77 python -c os.environ[SECRET] (T2.4)"       2 '{"tool_name":"Bash","tool_input":{"command":"python -c \"import os; print(os.environ['\''CLOUDFLARE_API_TOKEN'\''])\""}}'
run "78 node -e process.env.SECRET (T2.4)"         2 '{"tool_name":"Bash","tool_input":{"command":"node -e \"console.log(process.env.OP_SERVICE_ACCOUNT_TOKEN)\""}}'
run "79 ruby -e ENV[SECRET] (T2.4)"                2 '{"tool_name":"Bash","tool_input":{"command":"ruby -e \"puts ENV['\''ANTHROPIC_API_KEY'\'']\""}}'

# ---------------------------------------------------------------
# Section 8-10: should ALLOW (rc=0).
# ---------------------------------------------------------------

section "8. ALLOW -- safe forms for op read"
run "26 op read > file"                            0 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z > /tmp/cred"}}'
run "27 op read >> file"                           0 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z >> /tmp/cred"}}'
run "28 op read &> file (combined fd redirect)"    0 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z &> /tmp/cred"}}'
run "29 VAR=\$(op read ...)"                       0 '{"tool_name":"Bash","tool_input":{"command":"VAR=$(op read op://X/Y/z)"}}'
run "30 VAR=\`op read ...\`"                       0 '{"tool_name":"Bash","tool_input":{"command":"VAR=`op read op://X/Y/z`"}}'
run "31 op read | pbcopy"                          0 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z | pbcopy"}}'
run "32 op read | xclip"                           0 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z | xclip -selection clipboard"}}'
run "33 op read | wl-copy"                         0 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z | wl-copy"}}'

section "9. ALLOW -- v3 terminal-aware (redirect anywhere in pipeline)"
run "34 op read | jq | > file"                     0 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z | jq -r .field > /tmp/out"}}'
run "35 op read | tee | > /dev/null"               0 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z | tee /tmp/x > /dev/null"}}'
run "36 multi-stage with final redirect"           0 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z | jq . | tr -d '\''\\n'\'' > /tmp/y"}}'
run "37 mid-stage redirect (op read > file | x)"   0 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z > /tmp/x | something"}}'

section "10. ALLOW -- non-secret patterns"
run "38 VAR=\$(secret-cache-read FOO)"             0 '{"tool_name":"Bash","tool_input":{"command":"VAR=$(secret-cache-read FOO)"}}'
run "39 env -u (wrapper, not dump)"                0 '{"tool_name":"Bash","tool_input":{"command":"env -u OP_SERVICE_ACCOUNT_TOKEN op signin"}}'
run "40 env A=B cmd (wrapper)"                     0 '{"tool_name":"Bash","tool_input":{"command":"env FOO=bar /usr/local/bin/widget"}}'
run "41 dotfiles secret list (names only)"         0 '{"tool_name":"Bash","tool_input":{"command":"dotfiles secret list"}}'
run "42 echo \$PATH"                               0 '{"tool_name":"Bash","tool_input":{"command":"echo $PATH"}}'
run "43 bypass marker on jq"                       0 '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z | jq -r .  # secret-guard: allow"}}'
run "44 Read random file"                          0 '{"tool_name":"Read","tool_input":{"file_path":"/Users/tieubao/workspace/foo.md"}}'
run "45 Read secrets.fish.tmpl (template)"         0 '{"tool_name":"Read","tool_input":{"file_path":"/Users/tieubao/dotfiles/home/dot_config/fish/conf.d/secrets.fish.tmpl"}}'
run "46 Write normal markdown"                     0 '{"tool_name":"Write","tool_input":{"content":"# Normal markdown content with no secrets"}}'

section "10b. ALLOW -- audit-pass negatives (no expansion or non-secret)"
# Quoted heredoc marker prevents expansion -> body is literal -> no leak
# from $CLOUDFLARE_API_TOKEN textually appearing in the heredoc body.
run "56 heredoc <<'\''EOF'\'' literal body (FN2 inverse)" 0 '{"tool_name":"Bash","tool_input":{"command":"cat <<'\''EOF'\''\n$CLOUDFLARE_API_TOKEN\nEOF"}}'

section "10c. ALLOW -- ultrathink-pass boundary cases"
# T1.1 inverse: SSH PUBLIC keys are safe (the .pub guard).
run "80 cat ~/.ssh/id_ed25519.pub (T1.1 pub)"      0 '{"tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_ed25519.pub"}}'
run "81 Read ~/.ssh/id_ed25519.pub (T1.1 pub)"     0 '{"tool_name":"Read","tool_input":{"file_path":"/Users/tieubao/.ssh/id_ed25519.pub"}}'
run "82 Read ~/.ssh/id_ed25519-cert.pub (T1.1)"    0 '{"tool_name":"Read","tool_input":{"file_path":"/Users/tieubao/.ssh/id_ed25519-cert.pub"}}'
# T1.2 inverse: bare op signin (no --raw) does not print a token.
run "83 op signin (no --raw) (T1.2)"               0 '{"tool_name":"Bash","tool_input":{"command":"op signin"}}'
# T1.2 with redirect: op item get --field captured to file.
run "84 op item get --reveal > file (T1.2)"        0 '{"tool_name":"Bash","tool_input":{"command":"op item get \"My Item\" --field credential --reveal > /tmp/cred"}}'
# T1.3 with capture: security find-generic-password into VAR.
run "85 VAR=\$(security find-generic-password -ws SVC) (T1.3)" 0 '{"tool_name":"Bash","tool_input":{"command":"VAR=$(security find-generic-password -ws SVC -a $USER)"}}'
# T2.2 inverse: set with flags is config, not dump.
run "86 set -e (T2.2 inverse)"                     0 '{"tool_name":"Bash","tool_input":{"command":"set -e"}}'
run "87 set -euo pipefail (T2.2 inverse)"          0 '{"tool_name":"Bash","tool_input":{"command":"set -euo pipefail"}}'
run "88 set -- arg1 arg2 (T2.2 inverse)"           0 '{"tool_name":"Bash","tool_input":{"command":"set -- arg1 arg2"}}'
# T2.2 with redirect: bare set > file is a deliberate dump to file.
run "89 set > /tmp/all-vars (T2.2)"                0 '{"tool_name":"Bash","tool_input":{"command":"set > /tmp/all-vars"}}'
# T2.3 with capture: gh auth token captured into VAR.
run "90 VAR=\$(gh auth token) (T2.3)"              0 '{"tool_name":"Bash","tool_input":{"command":"GH=$(gh auth token)"}}'
# T2.4 inverse: python script that does NOT touch env.
run "91 python -c print hello (T2.4 inverse)"      0 '{"tool_name":"Bash","tool_input":{"command":"python -c \"print('\''hello world'\'')\""}}'
# T2.4 inverse: python script touches env but no secret-named var.
run "92 python -c os.environ[PATH] (T2.4 inverse)" 0 '{"tool_name":"Bash","tool_input":{"command":"python -c \"import os; print(os.environ['\''PATH'\''])\""}}'
# T2.4 with redirect: secret-printing python with > file.
run "93 python -c env > file (T2.4)"               0 '{"tool_name":"Bash","tool_input":{"command":"python -c \"import os; print(os.environ['\''CLOUDFLARE_API_TOKEN'\''])\" > /tmp/x"}}'
# T2.5 with capture/redirect.
run "94 gpg --decrypt > file (T2.5)"               0 '{"tool_name":"Bash","tool_input":{"command":"gpg --decrypt secret.gpg > /tmp/plain"}}'
# Generic ALLOW: command unrelated to anything.
run "95 git status (T2 sanity)"                    0 '{"tool_name":"Bash","tool_input":{"command":"git status"}}'

section "10d. ALLOW -- canonical 'how to USE a secret' patterns (P1-P7)"
# P1: auto-loaded env var pass-through. The literal $VAR is in the
# command but the value expands at exec time and never appears in the
# transcript.
run "100 P1 curl with already-loaded env var"       0 '{"tool_name":"Bash","tool_input":{"command":"curl -H \"Authorization: Bearer $CLOUDFLARE_API_TOKEN\" https://api.example.com"}}'
run "101 P1 ssh with token in env"                  0 '{"tool_name":"Bash","tool_input":{"command":"ssh -i ~/.ssh/config_managed_key user@host"}}'
# P2: capture-then-use in same Bash call.
run "102 P2 capture then curl"                      0 '{"tool_name":"Bash","tool_input":{"command":"TOKEN=$(op read '\''op://X/Y/z'\''); curl -H \"Authorization: Bearer $TOKEN\" https://api.example.com"}}'
# P4: env-prefix exec, single statement.
run "103 P4 env-prefix exec"                        0 '{"tool_name":"Bash","tool_input":{"command":"TOKEN=$(op read '\''op://X/Y/z'\'') my-app --auth-from-env"}}'
# P5: bash -c subshell with TOKEN env passed in.
run "104 P5 bash -c subshell"                       0 '{"tool_name":"Bash","tool_input":{"command":"TOKEN=$(op read '\''op://X/Y/z'\'') bash -c '\''curl -H \"Authorization: Bearer $TOKEN\" url'\''"}}'
# P6: process substitution into curl. Requires the new <(...) strip
# in is_safe_secret_call.
run "105 P6 curl -H @<(op read ...)"                0 '{"tool_name":"Bash","tool_input":{"command":"curl -H @<(op read '\''op://X/Y/z'\'') https://api.example.com"}}'
# P7: file-based handoff with cleanup.
run "106 P7 op read > file && cmd && rm"            0 '{"tool_name":"Bash","tool_input":{"command":"op read '\''op://X/Y/z'\'' > /tmp/auth && cmd --auth-file /tmp/auth && rm /tmp/auth"}}'

section "12. v3.4 -- audit-pass UX, log hygiene, defense-in-depth"

# A1: Edit on tests/secret-guard.sh is exempt despite pattern hits.
run "110 A1 Edit tests/secret-guard.sh allowed"     0 '{"tool_name":"Edit","tool_input":{"file_path":"/Users/tieubao/workspace/tieubao/dotfiles/tests/secret-guard.sh","old_string":"old","new_string":"new with '"$FAKE_SK_ANT"' inside"}}'
run "111 A1 Edit cheatsheet allowed"                0 '{"tool_name":"Write","tool_input":{"file_path":"/Users/tieubao/workspace/tieubao/dotfiles/docs/secret-handling-cheatsheet.md","content":"docs may show pattern names like '"$FAKE_SK_ANT"' as examples"}}'
run "112 A1 unrelated Edit still blocks"            2 '{"tool_name":"Edit","tool_input":{"file_path":"/Users/tieubao/notes.md","old_string":"old","new_string":"export ANTHROPIC='"$FAKE_SK_ANT"'"}}'

# D1: audit log entries include session_id and tool_name.
section "12b. D1 -- audit log format"
LOG_FILE="${HOME}/.cache/claude-secret-guard.log"
printf '%s' '{"session_id":"test-session-D1","tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z"}}' | bash "$HOOK" >/dev/null 2>&1
LOG_LINE=$(tail -1 "$LOG_FILE" 2>/dev/null)
if printf '%s' "$LOG_LINE" | grep -q '\[BLOCK\] \[test-session-D1\] \[Bash\]'; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  113 D1 audit-log entry has [STATUS] [session] [tool]"
else
    FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("113 D1 audit log format")
    echo "FAIL  113 D1 audit log format -- last line: $LOG_LINE"
fi

# Bypass-marker invocations are also logged as [BYPASS].
printf '%s' '{"session_id":"test-session-D1b","tool_name":"Bash","tool_input":{"command":"echo $MY_TOKEN # secret-guard: allow"}}' | bash "$HOOK" >/dev/null 2>&1
LOG_LINE=$(tail -1 "$LOG_FILE" 2>/dev/null)
if printf '%s' "$LOG_LINE" | grep -q '\[BYPASS\] \[test-session-D1b\] \[Bash\]'; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  114 D1 audit log records BYPASS uses"
else
    FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("114 D1 audit log records bypasses")
    echo "FAIL  114 D1 bypass logging -- last line: $LOG_LINE"
fi

# B1: PostToolUse hook detects credential pattern in tool_response.
section "12c. B1 -- PostToolUse warn-only"
POST_HOOK="$REPO_ROOT/home/dot_claude/hooks/secret-guard/executable_secret-guard-post.sh"
if [ -f "$POST_HOOK" ]; then
    OUT=$(printf '%s' '{"session_id":"test-session-B1","tool_name":"Bash","tool_input":{"command":"some-cmd"},"tool_response":{"stdout":"key='"$FAKE_AKIA"' leaked"}}' | bash "$POST_HOOK" 2>&1)
    RC=$?
    LOG_LINE=$(tail -1 "$LOG_FILE" 2>/dev/null)
    if [ "$RC" -eq 0 ] && printf '%s' "$LOG_LINE" | grep -q '\[POST-LEAK\]'; then
        PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  115 B1 PostToolUse logs POST-LEAK on AWS key in stdout"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("115 B1 PostToolUse warn")
        echo "FAIL  115 B1 PostToolUse (rc=$RC) -- last line: $LOG_LINE"
    fi
    OUT=$(printf '%s' '{"session_id":"test-session-B1c","tool_name":"Bash","tool_input":{"command":"x"},"tool_response":{"stdout":"normal output, no secrets"}}' | bash "$POST_HOOK" 2>&1)
    RC=$?
    if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
        PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  116 B1 PostToolUse silent on clean output"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("116 B1 PostToolUse silent")
        echo "FAIL  116 B1 PostToolUse not silent (rc=$RC, OUT=$OUT)"
    fi
else
    echo "SKIP  115/116 (PostToolUse hook script not present)"
fi

# v3.5 -- MODE switch + per-rule guidance
section "12e. v3.5 -- MODE switch (warn-only / off)"

# warn-only mode: same patterns, but exit 0 and print "WARN-ONLY" header.
OUT=$(printf '%s' '{"session_id":"sg-mode","tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z"}}' \
    | SECRET_GUARD_MODE=warn-only bash "$HOOK" 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'WARN-ONLY: secret leak'; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  120 v3.5 warn-only mode exits 0 with WARN-ONLY header"
else
    FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("120 warn-only mode")
    echo "FAIL  120 warn-only (rc=$RC)"
fi

# off mode: silent exit 0, no stderr.
OUT=$(printf '%s' '{"session_id":"sg-mode","tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z"}}' \
    | SECRET_GUARD_MODE=off bash "$HOOK" 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  121 v3.5 off mode silent exit 0"
else
    FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("121 off mode")
    echo "FAIL  121 off mode (rc=$RC, OUT=$OUT)"
fi

# Per-rule guidance: B5 block message includes B5-specific recipe.
OUT=$(printf '%s' '{"session_id":"sg-rule","tool_name":"Bash","tool_input":{"command":"cat ~/.netrc"}}' | bash "$HOOK" 2>&1)
RC=$?
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'S-62/B5' && printf '%s' "$OUT" | grep -q 'rendered secret values'; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  122 v3.5 B5 block message has B5-specific guidance"
else
    FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("122 B5 per-rule guidance")
    echo "FAIL  122 B5 guidance (rc=$RC)"
fi

# Per-rule guidance: B7 (literal credential in command).
OUT=$(printf '%s' '{"session_id":"sg-rule","tool_name":"Bash","tool_input":{"command":"http POST https://x.example/auth Authorization:\"Bearer '"$FAKE_SK_ANT"'\""}}' | bash "$HOOK" 2>&1)
RC=$?
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'S-62/B7' && printf '%s' "$OUT" | grep -q "Replace the literal credential"; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  123 v3.5 B7 block message has B7-specific guidance"
else
    FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("123 B7 per-rule guidance")
    echo "FAIL  123 B7 guidance (rc=$RC)"
fi

# B2: Stop hook detects credential pattern in last assistant message.
section "12d. B2 -- Stop hook warn-only"
STOP_HOOK="$REPO_ROOT/home/dot_claude/hooks/secret-guard/executable_secret-guard-stop.sh"
if [ -f "$STOP_HOOK" ]; then
    # Build a fake transcript with a leaked sk-ant pattern in the last assistant message.
    TMPDIR_T=$(mktemp -d)
    TRANSCRIPT="$TMPDIR_T/fake.jsonl"
    {
        printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}'
        printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi there"}]}}'
        printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"give me a secret"}]}}'
        printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"here it is: '"$FAKE_SK_ANT"'"}]}}'
    } > "$TRANSCRIPT"
    OUT=$(printf '%s' "{\"session_id\":\"test-session-B2\",\"transcript_path\":\"$TRANSCRIPT\"}" | bash "$STOP_HOOK" 2>&1)
    RC=$?
    LOG_LINE=$(tail -1 "$LOG_FILE" 2>/dev/null)
    if [ "$RC" -eq 0 ] && printf '%s' "$LOG_LINE" | grep -q '\[STOP-LEAK\]'; then
        PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  117 B2 Stop hook logs STOP-LEAK on sk-ant in last assistant message"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("117 B2 Stop warn")
        echo "FAIL  117 B2 Stop hook (rc=$RC) -- last line: $LOG_LINE"
    fi
    rm -f "$TRANSCRIPT"
    rmdir "$TMPDIR_T" 2>/dev/null || true
else
    echo "SKIP  117 (Stop hook script not present)"
fi

# ---------------------------------------------------------------
# Section 11: plumbing / fail-open (rc=0; integrity).
# ---------------------------------------------------------------

section "11. PLUMBING -- shellcheck, idempotency, fail-open"

# 47-48 lint
LINT=$(shellcheck --severity=warning "$HOOK" 2>&1)
if [ -z "$LINT" ]; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  47 shellcheck on hook script"
else
    FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("47 shellcheck on hook script")
    echo "FAIL  47 shellcheck on hook script"; printf '%s\n' "$LINT" | sed 's/^/        /'
fi

LINT_MOD=$(shellcheck --severity=warning "$REPO_ROOT/home/dot_claude/modify_settings.json" 2>&1)
if [ -z "$LINT_MOD" ]; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  48 shellcheck on modify_settings.json"
else
    FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("48 shellcheck on modify_settings.json")
    echo "FAIL  48 shellcheck on modify_settings.json"; printf '%s\n' "$LINT_MOD" | sed 's/^/        /'
fi

# 49 idempotency: f(f(x)) == f(x)
SETTINGS_LIVE="${HOME}/.claude/settings.json"
if [ -r "$SETTINGS_LIVE" ]; then
    P1=$(bash "$REPO_ROOT/home/dot_claude/modify_settings.json" < "$SETTINGS_LIVE")
    P2=$(printf '%s' "$P1" | bash "$REPO_ROOT/home/dot_claude/modify_settings.json")
    if diff <(printf '%s' "$P1" | jq -S .) <(printf '%s' "$P2" | jq -S .) > /dev/null 2>&1; then
        PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  49 modify_settings.json idempotent"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("49 modify_settings.json idempotent")
        echo "FAIL  49 modify_settings.json idempotent"
    fi
else
    echo "SKIP  49 (no live settings.json at $SETTINGS_LIVE)"
fi

# 50 chezmoi diff sanity (only run if chezmoi sees the script)
if command -v chezmoi >/dev/null 2>&1 && chezmoi managed 2>/dev/null | grep -q secret-guard; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  50 chezmoi managed sees secret-guard.sh"
else
    echo "SKIP  50 (chezmoi missing or hook not yet managed)"
fi

# 51-52 fail-open
# Test 51: jq missing. macOS ships /usr/bin/jq so PATH-stripping
# doesn't isolate it; instead we copy the hook into a temp file with
# the `command -v jq` line patched to look up a non-existent command,
# exercising the same fail-open branch.
TMP_HOOK=$(mktemp -t secret-guard-test-XXXXXX) || TMP_HOOK="/tmp/secret-guard-test-$$.sh"
sed 's|command -v jq |command -v __secret_guard_test_missing_jq__ |' "$HOOK" > "$TMP_HOOK"
out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"op read op://X/Y/z"}}' | bash "$TMP_HOOK" 2>&1)
rc=$?
rm -f "$TMP_HOOK"
if [ "$rc" -eq 0 ]; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  51 fails open when jq is missing"
else
    FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("51 fail-open on missing jq")
    echo "FAIL  51 fail-open on missing jq (rc=$rc)"
fi
out=$(printf 'not-json' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS  52 fails open on malformed JSON"
else
    FAIL_COUNT=$((FAIL_COUNT + 1)); FAILED_LABELS+=("52 fail-open on malformed JSON")
    echo "FAIL  52 fail-open on malformed JSON (rc=$rc)"
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "==============================================="
    printf '  %d/%d tests passed (S-62)\n' "$PASS_COUNT" "$TOTAL"
    echo "==============================================="
    exit 0
else
    echo "==============================================="
    printf '  %d/%d tests passed, %d failed:\n' "$PASS_COUNT" "$TOTAL" "$FAIL_COUNT"
    for label in "${FAILED_LABELS[@]}"; do
        printf '    - %s\n' "$label"
    done
    echo "==============================================="
    exit 1
fi
