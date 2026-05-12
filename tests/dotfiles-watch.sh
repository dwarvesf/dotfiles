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
FSWATCH_PLIST_TMPL="$REPO_ROOT/home/Library/LaunchAgents/com.truonghan.dotfiles-watcher-fswatch.plist.tmpl"
WIRE_TMPL="$REPO_ROOT/home/.chezmoiscripts/run_onchange_after_dotfiles-watcher.sh.tmpl"
BREWFILE_TMPL="$REPO_ROOT/home/dot_Brewfile.tmpl"

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
run "1.1 shellcheck dotfiles-watcher-tick"     test_shellcheck_tick
run "1.2 shellcheck dotfiles-watcher-fswatch"  test_shellcheck_fswatch

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
# 5. Brewfile entry
# ---------------------------------------------------------------
section "5. Brewfile"

test_brewfile_has_fswatch() {
    grep -q '^brew "fswatch"' "$BREWFILE_TMPL"
}
run "5.1 home/dot_Brewfile.tmpl contains fswatch" test_brewfile_has_fswatch

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
