#!/usr/bin/env bash
# tests/dotfiles-watch.sh -- spec test matrix for S-64.
#
# Self-contained: no bats, no test framework. Each test is a bash function
# that returns 0 on pass, non-zero on fail. Exits 0 iff every test passes.
#
# Usage:
#   bash tests/dotfiles-watch.sh
#   bash tests/dotfiles-watch.sh --verbose
#
# Coverage maps to S-64 § Test cases 1-7.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TICK="$REPO_ROOT/home/dot_local/bin/executable_dotfiles-watcher-tick"
FSWATCH_WRAP="$REPO_ROOT/home/dot_local/bin/executable_dotfiles-watcher-fswatch"
DOCTOR="$REPO_ROOT/home/dot_local/bin/executable_dotfiles-watch-doctor"
FSWATCH_PLIST_TMPL="$REPO_ROOT/home/Library/LaunchAgents/com.truonghan.dotfiles-watcher-fswatch.plist.tmpl"
WIRE_TMPL="$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_dotfiles-watcher.sh.tmpl"
BREWFILE_TMPL="$REPO_ROOT/home/dot_Brewfile.tmpl"
SYNC_SKILL="$REPO_ROOT/home/dot_claude/commands/dotfiles-sync.md"

VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

PASS=0
FAIL=0
FAILED=()

run() {
    local label="$1"; shift
    local out rc
    out=$("$@" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
        printf 'PASS  %s\n' "$label"
        PASS=$((PASS + 1))
        [ "$VERBOSE" -eq 1 ] && [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/        /'
    else
        printf 'FAIL  %s\n' "$label"
        printf '%s\n' "$out" | sed 's/^/        /'
        FAIL=$((FAIL + 1))
        FAILED+=("$label")
    fi
}

section() { printf '\n--- %s ---\n' "$*"; }

# ---------------------------------------------------------------
# Helper: write a fake chezmoi shim. Behavior is driven by env vars
# the test sets before invoking the tick wrapper.
#
#   FAKE_MANAGED         newline-list of paths emitted by `chezmoi managed`
#   FAKE_STATUS_LINES    newline-list; the Nth line is emitted on the Nth
#                        `chezmoi status` call (counter at $FAKE_STATE/iter)
#   FAKE_STATE           dir for state files; default /tmp
# ---------------------------------------------------------------
_make_fake_chezmoi() {
    local bin="$1"
    mkdir -p "$bin"
    cat > "$bin/chezmoi" <<'SHIM'
#!/bin/sh
state="${FAKE_STATE:-/tmp}"
mkdir -p "$state"
case "${1:-}" in
    managed)
        [ -n "${FAKE_MANAGED:-}" ] && printf '%s\n' "$FAKE_MANAGED"
        exit 0
        ;;
    data)
        # S-66 doctor probes `chezmoi data` for headless. Default false.
        printf '{"headless": %s}\n' "${FAKE_HEADLESS:-false}"
        exit 0
        ;;
    status)
        iter=0
        [ -f "$state/iter" ] && iter=$(cat "$state/iter")
        iter=$((iter + 1))
        echo "$iter" > "$state/iter"
        printf '%s\n' "${FAKE_STATUS_LINES:-}" | sed -n "${iter}p"
        exit 0
        ;;
    re-add)
        shift
        echo "$@" >> "$state/readd"
        exit 0
        ;;
    add)
        shift
        echo "$@" >> "$state/added"
        exit 0
        ;;
esac
exit 0
SHIM
    chmod +x "$bin/chezmoi"
}

_setup_fake_home() {
    local home="$1"
    mkdir -p "$home/.local/bin" "$home/Library/Logs" "$home/Library/Caches"
    _make_fake_chezmoi "$home/.local/bin"
    export FAKE_STATE="$home/.fake-state"
    mkdir -p "$FAKE_STATE"
}

_run_tick() {
    local home="$1"
    HOME="$home" DOTFILES_CHEZMOI="$home/.local/bin/chezmoi" bash "$TICK"
}

# ---------------------------------------------------------------
# 1. Lint
# ---------------------------------------------------------------
section "1. Lint"

test_shellcheck_tick() {
    shellcheck -e SC2015 "$TICK"
}
test_shellcheck_fswatch() {
    shellcheck -e SC2015 "$FSWATCH_WRAP"
}
test_shellcheck_doctor() {
    shellcheck -e SC2015 "$DOCTOR"
}
run "1.1 shellcheck dotfiles-watcher-tick"     test_shellcheck_tick
run "1.2 shellcheck dotfiles-watcher-fswatch"  test_shellcheck_fswatch
run "1.3 shellcheck dotfiles-watch-doctor"     test_shellcheck_doctor

# ---------------------------------------------------------------
# 2. Templates render and lint
# ---------------------------------------------------------------
section "2. Templates"

test_fswatch_plist_render() {
    local tmp rc
    tmp=$(mktemp)
    chezmoi execute-template < "$FSWATCH_PLIST_TMPL" > "$tmp" 2>/dev/null
    /usr/bin/plutil -lint "$tmp" >/dev/null
    rc=$?
    rm -f "$tmp"
    return $rc
}
test_wire_script_render() {
    local tmp rc
    tmp=$(mktemp)
    chezmoi execute-template < "$WIRE_TMPL" > "$tmp" 2>/dev/null
    bash -n "$tmp"
    rc=$?
    rm -f "$tmp"
    return $rc
}
if command -v chezmoi >/dev/null 2>&1; then
    run "2.1 fswatch plist template -> plutil lint"  test_fswatch_plist_render
    run "2.2 run_onchange template -> bash -n"       test_wire_script_render
else
    printf 'SKIP  2.1 / 2.2 (chezmoi not on PATH)\n'
fi

# ---------------------------------------------------------------
# 3. Tick behavior with fake chezmoi
# ---------------------------------------------------------------
section "3. Tick behavior"

test_noop_when_clean() {
    local home
    home=$(mktemp -d)
    _setup_fake_home "$home"
    export FAKE_STATUS_LINES=""
    _run_tick "$home" || { rm -rf "$home"; return 1; }
    if [ -s "$home/Library/Logs/dotfiles-watcher.log" ]; then
        echo "log should be empty on clean status"
        cat "$home/Library/Logs/dotfiles-watcher.log"
        rm -rf "$home"
        return 1
    fi
    rm -rf "$home"
    return 0
}

test_single_pass_absorb() {
    local home
    home=$(mktemp -d)
    _setup_fake_home "$home"
    export FAKE_STATUS_LINES=$' M .claude/settings.json'
    _run_tick "$home" || { rm -rf "$home"; return 1; }
    local log="$home/Library/Logs/dotfiles-watcher.log"
    grep -q 'TICK start' "$log"             || { echo "missing TICK start"; cat "$log"; rm -rf "$home"; return 1; }
    grep -q 'TICK done (passes=1)' "$log"   || { echo "expected passes=1"; cat "$log"; rm -rf "$home"; return 1; }
    grep -q '+ .claude/settings.json' "$log" || { echo "missing absorbed-file line"; cat "$log"; rm -rf "$home"; return 1; }
    rm -rf "$home"
    return 0
}

test_drift_loop_iterates() {
    local home
    home=$(mktemp -d)
    _setup_fake_home "$home"
    export FAKE_STATUS_LINES=$' M .claude/CLAUDE.md\n M .claude/settings.json'
    _run_tick "$home" || { rm -rf "$home"; return 1; }
    local log="$home/Library/Logs/dotfiles-watcher.log"
    grep -q 'TICK done (passes=2)' "$log" || {
        echo "expected passes=2 in log"
        cat "$log"
        rm -rf "$home"
        return 1
    }
    rm -rf "$home"
    return 0
}

test_lock_coalesces() {
    local home
    home=$(mktemp -d)
    _setup_fake_home "$home"
    export FAKE_STATUS_LINES=$' M .claude/CLAUDE.md'
    HOME="$home" DOTFILES_CHEZMOI="$home/.local/bin/chezmoi" bash "$TICK" &
    local pid1=$!
    HOME="$home" DOTFILES_CHEZMOI="$home/.local/bin/chezmoi" bash "$TICK" &
    local pid2=$!
    wait "$pid1" "$pid2"
    local log="$home/Library/Logs/dotfiles-watcher.log"
    local n
    n=$(grep -c 'TICK start' "$log" 2>/dev/null || echo 0)
    if [ "$n" != "1" ]; then
        echo "expected exactly 1 TICK start, got $n"
        cat "$log"
        rm -rf "$home"
        return 1
    fi
    rm -rf "$home"
    return 0
}

test_absorb_MM_status() {
    # MM in chezmoi status means both source and destination changed since
    # last apply. The watcher must still absorb (dest changed = live edit).
    # Was a real bug found during S-64 deploy on Mac mini.
    local home
    home=$(mktemp -d)
    _setup_fake_home "$home"
    export FAKE_STATUS_LINES=$'MM .tool-versions'
    _run_tick "$home" || { rm -rf "$home"; return 1; }
    local log="$home/Library/Logs/dotfiles-watcher.log"
    grep -q 'TICK start' "$log" || { echo "MM row not absorbed"; cat "$log"; rm -rf "$home"; return 1; }
    grep -q '+ .tool-versions' "$log" || { echo "missing absorbed-file line"; cat "$log"; rm -rf "$home"; return 1; }
    rm -rf "$home"
    return 0
}

run "3.1 no-op when chezmoi status clean"   test_noop_when_clean
run "3.2 absorb single-pass drift"          test_single_pass_absorb
run "3.3 drift loop iterates until clean"   test_drift_loop_iterates
run "3.4 mkdir-lock coalesces parallel"     test_lock_coalesces
run "3.5 absorb MM (both-changed) row"      test_absorb_MM_status

# ---------------------------------------------------------------
# 3b. Auto-enroll (S-67)
#
# AUTO_ENROLL_GLOBS in the tick currently has one entry:
#     ${HOME}/.claude/skills/*/SKILL.md
# Tests below exercise enroll, idempotency, glob discipline, and the
# enroll+absorb mixed case.
# ---------------------------------------------------------------
section "3b. Auto-enroll (S-67)"

test_enroll_new_skill() {
    local home
    home=$(mktemp -d)
    _setup_fake_home "$home"
    mkdir -p "$home/.claude/skills/foo"
    echo "test skill" > "$home/.claude/skills/foo/SKILL.md"
    export FAKE_MANAGED=""
    export FAKE_STATUS_LINES=""
    _run_tick "$home" || { rm -rf "$home"; return 1; }
    local log="$home/Library/Logs/dotfiles-watcher.log"
    grep -q '+ enrolled .claude/skills/foo/SKILL.md' "$log" || {
        echo "missing + enrolled line"
        cat "$log" 2>/dev/null
        rm -rf "$home"
        return 1
    }
    # Verify chezmoi add actually got the absolute path.
    grep -Fq "$home/.claude/skills/foo/SKILL.md" "$home/.fake-state/added" 2>/dev/null || {
        echo "chezmoi add was not called with the expected path"
        cat "$home/.fake-state/added" 2>/dev/null
        rm -rf "$home"
        return 1
    }
    rm -rf "$home"
    return 0
}

test_enroll_idempotent_when_managed() {
    local home
    home=$(mktemp -d)
    _setup_fake_home "$home"
    mkdir -p "$home/.claude/skills/foo"
    echo "test skill" > "$home/.claude/skills/foo/SKILL.md"
    export FAKE_MANAGED=".claude/skills/foo/SKILL.md"
    export FAKE_STATUS_LINES=""
    _run_tick "$home" || { rm -rf "$home"; return 1; }
    local log="$home/Library/Logs/dotfiles-watcher.log"
    if grep -q '+ enrolled' "$log" 2>/dev/null; then
        echo "should not enroll an already-managed file"
        cat "$log"
        rm -rf "$home"
        return 1
    fi
    if [ -s "$home/.fake-state/added" ]; then
        echo "chezmoi add was called on an already-managed file"
        cat "$home/.fake-state/added"
        rm -rf "$home"
        return 1
    fi
    rm -rf "$home"
    return 0
}

test_enroll_glob_discipline() {
    # Non-SKILL.md files inside a skill dir must not be enrolled.
    local home
    home=$(mktemp -d)
    _setup_fake_home "$home"
    mkdir -p "$home/.claude/skills/foo"
    echo "readme" > "$home/.claude/skills/foo/README.md"
    export FAKE_MANAGED=""
    export FAKE_STATUS_LINES=""
    _run_tick "$home" || { rm -rf "$home"; return 1; }
    local log="$home/Library/Logs/dotfiles-watcher.log"
    if grep -q '+ enrolled' "$log" 2>/dev/null; then
        echo "README.md should not match the SKILL.md glob"
        cat "$log"
        rm -rf "$home"
        return 1
    fi
    if [ -s "$home/.fake-state/added" ]; then
        echo "chezmoi add was called on a non-SKILL file"
        cat "$home/.fake-state/added"
        rm -rf "$home"
        return 1
    fi
    rm -rf "$home"
    return 0
}

test_enroll_and_absorb_mixed() {
    # Enrollment AND drift absorb in the same tick. Log should show both,
    # passes=1 (one drift-loop iteration).
    local home
    home=$(mktemp -d)
    _setup_fake_home "$home"
    mkdir -p "$home/.claude/skills/new"
    echo "new skill" > "$home/.claude/skills/new/SKILL.md"
    export FAKE_MANAGED=""
    export FAKE_STATUS_LINES=$' M .claude/settings.json'
    _run_tick "$home" || { rm -rf "$home"; return 1; }
    local log="$home/Library/Logs/dotfiles-watcher.log"
    grep -q '+ enrolled .claude/skills/new/SKILL.md' "$log" || {
        echo "missing enrolled line"
        cat "$log"
        rm -rf "$home"
        return 1
    }
    grep -q '+ .claude/settings.json' "$log" || {
        echo "missing absorb line"
        cat "$log"
        rm -rf "$home"
        return 1
    }
    grep -q 'TICK done (passes=1)' "$log" || {
        echo "expected passes=1"
        cat "$log"
        rm -rf "$home"
        return 1
    }
    # Exactly one TICK start (enrollment block opens it; drift loop must not reopen).
    local starts
    starts=$(grep -c 'TICK start' "$log")
    if [ "$starts" != "1" ]; then
        echo "expected 1 TICK start line, got $starts"
        cat "$log"
        rm -rf "$home"
        return 1
    fi
    rm -rf "$home"
    return 0
}

run "3b.1 enroll new SKILL.md (unmanaged)"          test_enroll_new_skill
run "3b.2 enroll idempotent on already-managed"     test_enroll_idempotent_when_managed
run "3b.3 enroll glob excludes non-SKILL.md"        test_enroll_glob_discipline
run "3b.4 enroll + absorb in one tick"              test_enroll_and_absorb_mixed

# ---------------------------------------------------------------
# 4. dotfiles-watch-doctor (S-66 health audit)
# ---------------------------------------------------------------
section "4. Doctor (S-66)"

# Helper: write a fake launchctl. Behavior driven by env vars
#   FAKE_LC_WP=running|loaded|missing
#   FAKE_LC_FS=running|loaded|missing
_make_fake_launchctl() {
    local bin="$1"
    cat > "$bin/launchctl" <<'SHIM'
#!/bin/sh
target="$2"
case "$target" in
    *com.truonghan.dotfiles-watcher-fswatch) flag="${FAKE_LC_FS:-running}";;
    *com.truonghan.dotfiles-watcher)         flag="${FAKE_LC_WP:-running}";;
    *)                                       exit 1;;
esac
case "$flag" in
    running) echo "	state = running"; exit 0;;
    loaded)  echo "	state = waiting"; exit 0;;
    missing) exit 1;;
esac
exit 1
SHIM
    chmod +x "$bin/launchctl"
}

# Helper: write a fake fswatch shim (test 4.5 deletes it to simulate missing).
_make_fake_fswatch() {
    local bin="$1"
    cat > "$bin/fswatch" <<'SHIM'
#!/bin/sh
[ "$1" = "--version" ] && { echo "fswatch 1.18.0 (fake)"; exit 0; }
exit 0
SHIM
    chmod +x "$bin/fswatch"
}

_setup_doctor_home() {
    local home="$1"
    mkdir -p "$home/.local/bin" "$home/.cache" \
             "$home/Library/Logs" "$home/Library/Caches" \
             "$home/Library/LaunchAgents" "$home/.shims"
    _make_fake_chezmoi "$home/.local/bin"
    _make_fake_launchctl "$home/.shims"
    _make_fake_fswatch "$home/.shims"
}

_seed_clean_fingerprint() {
    local home="$1"
    printf '' | sha256sum | awk '{print $1}' \
        > "$home/.cache/dotfiles-watcher.managed.sha256"
}

_run_doctor() {
    local home="$1"
    HOME="$home" \
    PATH="$home/.shims:$home/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    DOTFILES_CHEZMOI="$home/.local/bin/chezmoi" \
        sh "$DOCTOR"
}

test_doctor_clean() {
    local home out rc
    home=$(mktemp -d)
    _setup_doctor_home "$home"
    _seed_clean_fingerprint "$home"
    out=$(FAKE_MANAGED="" FAKE_LC_WP=running FAKE_LC_FS=running _run_doctor "$home" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "expected exit 0, got $rc"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    if echo "$out" | grep -qE '^\[(warn|err)\]'; then
        echo "unexpected warn/err on clean state:"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    rm -rf "$home"
    return 0
}

# S-68: a WatchPaths-only agent is `state = waiting` (loaded but not currently
# ticking) the vast majority of the time. The doctor must treat this as [ok],
# not [err]. Pre-S-68 this fired a false-positive on every idle deploy.
test_doctor_agent_wp_idle() {
    local home out rc
    home=$(mktemp -d)
    _setup_doctor_home "$home"
    _seed_clean_fingerprint "$home"
    out=$(FAKE_MANAGED="" FAKE_LC_WP=loaded FAKE_LC_FS=running _run_doctor "$home" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "expected exit 0 for idle WP agent, got $rc"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    if echo "$out" | grep -qE '^\[(warn|err)\][[:space:]]+agent: com.truonghan.dotfiles-watcher\b'; then
        echo "idle WP agent should be [ok], not warn/err:"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    if ! echo "$out" | grep -qE '^\[ok\][[:space:]]+agent: com.truonghan.dotfiles-watcher loaded'; then
        echo "missing expected [ok] line for idle WP agent"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    rm -rf "$home"
    return 0
}

test_doctor_agent_wp_missing() {
    local home out rc
    home=$(mktemp -d)
    _setup_doctor_home "$home"
    _seed_clean_fingerprint "$home"
    out=$(FAKE_MANAGED="" FAKE_LC_WP=missing FAKE_LC_FS=running _run_doctor "$home" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "expected non-zero exit, got 0"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    if ! echo "$out" | grep -qE '^\[err\][[:space:]]+agent: com.truonghan.dotfiles-watcher not loaded'; then
        echo "missing [err] line for agent-wp"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    rm -rf "$home"
    return 0
}

test_doctor_plist_drift() {
    local home out rc
    home=$(mktemp -d)
    _setup_doctor_home "$home"
    # Non-hex sentinel so secret-guard doesn't see it as a 64-hex private key.
    echo "stale-fingerprint-non-hex-sentinel" \
        > "$home/.cache/dotfiles-watcher.managed.sha256"
    out=$(FAKE_MANAGED=".claude/CLAUDE.md
.config/zed/settings.json" \
          FAKE_LC_WP=running FAKE_LC_FS=running _run_doctor "$home" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "expected non-zero exit, got 0"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    if ! echo "$out" | grep -qE '^\[warn\][[:space:]]+plist fingerprint: managed-set drifted'; then
        echo "missing [warn] for plist fingerprint drift"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    rm -rf "$home"
    return 0
}

test_doctor_lock_stale() {
    local home out rc
    home=$(mktemp -d)
    _setup_doctor_home "$home"
    _seed_clean_fingerprint "$home"
    mkdir -p "$home/Library/Caches/dotfiles-watcher.lock"
    local lock_mtime
    lock_mtime=$(stat -f %m "$home/Library/Caches/dotfiles-watcher.lock")
    out=$(FAKE_MANAGED="" FAKE_LC_WP=running FAKE_LC_FS=running \
          NOW_OVERRIDE=$((lock_mtime + 3600)) _run_doctor "$home" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "expected non-zero exit, got 0"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    if ! echo "$out" | grep -qE '^\[warn\][[:space:]]+lock: stale'; then
        echo "missing [warn] for stale lock"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    rm -rf "$home"
    return 0
}

test_doctor_fswatch_missing() {
    local home out rc
    home=$(mktemp -d)
    _setup_doctor_home "$home"
    _seed_clean_fingerprint "$home"
    rm -f "$home/.shims/fswatch"
    out=$(FAKE_MANAGED="" FAKE_LC_WP=running FAKE_LC_FS=running _run_doctor "$home" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "expected non-zero exit, got 0"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    if ! echo "$out" | grep -qE '^\[err\][[:space:]]+fswatch: missing'; then
        echo "missing [err] for fswatch missing"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    rm -rf "$home"
    return 0
}

test_doctor_headless_skip() {
    local home out rc
    home=$(mktemp -d)
    _setup_doctor_home "$home"
    out=$(FAKE_HEADLESS=true _run_doctor "$home" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "headless should exit 0, got $rc"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    if ! echo "$out" | grep -qE '^\[ok\][[:space:]]+watcher: headless'; then
        echo "missing [ok] headless line"
        echo "$out"
        rm -rf "$home"
        return 1
    fi
    rm -rf "$home"
    return 0
}

test_sync_skill_calls_doctor() {
    grep -F "dotfiles watch doctor" "$SYNC_SKILL" >/dev/null
}

test_wiring_script_writes_fingerprint() {
    grep -F "dotfiles-watcher.managed.sha256" "$WIRE_TMPL" >/dev/null
}

run "4.1 doctor exits 0 on a clean machine"          test_doctor_clean
run "4.1b doctor exits 0 on an idle WP agent (S-68)" test_doctor_agent_wp_idle
run "4.2 doctor errs when WatchPaths agent missing"  test_doctor_agent_wp_missing
run "4.3 doctor warns on plist fingerprint drift"    test_doctor_plist_drift
run "4.4 doctor warns on stale lock (>60s)"          test_doctor_lock_stale
run "4.5 doctor errs when fswatch binary missing"    test_doctor_fswatch_missing
run "4.6 doctor self-skips on headless"              test_doctor_headless_skip
run "4.7 /dotfiles-sync skill invokes doctor"        test_sync_skill_calls_doctor
run "4.8 wiring script caches managed fingerprint"   test_wiring_script_writes_fingerprint

# ---------------------------------------------------------------
# 5. Brewfile entry
# ---------------------------------------------------------------
section "5. Brewfile"

test_brewfile_has_fswatch() {
    grep -q '^brew "fswatch"' "$BREWFILE_TMPL"
}
run "5.1 home/dot_Brewfile.tmpl contains fswatch" test_brewfile_has_fswatch

# ---------------------------------------------------------------
# 6. Docs cross-references (S-65 post-ship sweep)
# ---------------------------------------------------------------
section "6. Docs cross-references (S-65)"

LLM_DOTFILES="$REPO_ROOT/docs/llm-dotfiles.md"
README="$REPO_ROOT/README.md"
INSTALL_SH="$REPO_ROOT/install.sh"
SYNC_SKILL="$REPO_ROOT/home/dot_claude/commands/dotfiles-sync.md"
ADR_006="$REPO_ROOT/docs/decisions/006-auto-commit-workflow.md"

test_no_stale_no_daemon_claim() {
    # The pre-S-64 sentence "No daemon, no watcher" was actively wrong post-ship.
    # Must not reappear.
    ! grep -F "No daemon, no watcher" "$LLM_DOTFILES"
}
test_llm_dotfiles_mentions_watcher() {
    grep -F "dotfiles watch" "$LLM_DOTFILES" >/dev/null && grep -F "S-64" "$LLM_DOTFILES" >/dev/null
}
test_readme_cheat_sheet_has_watcher() {
    grep -F "dotfiles watch" "$README" >/dev/null
}
test_readme_cross_references_s64() {
    grep -F "S-64" "$README" >/dev/null
}
test_install_sh_mentions_watcher() {
    grep -F "dotfiles watch" "$INSTALL_SH" >/dev/null
}
test_sync_skill_acknowledges_watcher() {
    grep -F "dotfiles watch" "$SYNC_SKILL" >/dev/null
}
test_adr_006_has_watcher_exception() {
    # Either a "S-64" cross-reference or "exception" framing around the watcher.
    grep -E "S-64|watcher.*exception|exception.*watcher" "$ADR_006" >/dev/null
}

run "6.1 docs/llm-dotfiles.md no stale 'No daemon, no watcher'"  test_no_stale_no_daemon_claim
run "6.2 docs/llm-dotfiles.md mentions watcher + S-64"           test_llm_dotfiles_mentions_watcher
run "6.3 README cheat sheet has watcher row"                     test_readme_cheat_sheet_has_watcher
run "6.4 README cross-references S-64"                           test_readme_cross_references_s64
run "6.5 install.sh hints at the watcher"                        test_install_sh_mentions_watcher
run "6.6 /dotfiles-sync skill Step 2 acknowledges watcher"       test_sync_skill_acknowledges_watcher
run "6.7 ADR-006 documents the watcher exception"                test_adr_006_has_watcher_exception

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
printf '\n=====================================\n'
printf 'PASS: %d   FAIL: %d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "Failed:"
    for label in "${FAILED[@]}"; do echo "  - $label"; done
    exit 1
fi
exit 0
