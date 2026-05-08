#!/usr/bin/env bash
# test-doc-discipline.sh
#
# Verifies the framework-vs-personal split for the S-51 multi-machine docs
# (extends to other framework docs as they're added).
#
# Contract:
# - "Framework docs" describe a forkable pattern. They MUST contain no
#   personal markers (specific hostnames, vault paths, SSH aliases).
# - "Operations cookbooks" record the author's specific application of a
#   pattern. They MUST contain personal markers (otherwise they're not
#   actually a record of anything done).
#
# Exit codes:
#   0  contract holds
#   1  contract violated (which file + which pattern is reported)
#
# Usage: ./scripts/test-doc-discipline.sh [--verbose]
set -euo pipefail

VERBOSE=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Files that MUST stay placeholder-clean (forkable framework artifacts).
# Adding code surface here too: help text, comments, and inline examples in
# framework code are also part of what a forker reads.
FRAMEWORK_DOCS=(
    "docs/specs/S-51-multi-machine-sa-access.md"
    "docs/specs/S-52-secrets-architecture-synthesis-doc.md"
    "docs/1password-multi-machine.md"
    "docs/secrets-architecture.md"
    "home/dot_config/fish/functions/dotfiles.fish"
    "home/dot_config/fish/conf.d/secrets.fish.tmpl"
    "home/dot_local/bin/executable_secret-cache-read"
)

# Files that ARE allowed to contain personal context (author's records).
# Each file in this list MUST contain at least one personal marker, otherwise
# the cookbook is suspiciously generic and we want to know.
OPERATIONS_DOCS=(
    "docs/operations/2026-05-mini-sa-seed.md"
)

# Personal markers. Assembled from parts so this script's source does not
# contain the matchable substrings verbatim (so this script could safely be
# scanned by itself in the future, and so the patterns don't leak into a
# doc-grep that includes scripts/).
HOST=$(printf '%s%s' 'mini-' 'tieubao')
USR=$(printf '%s%s' 'tieubao' '@')
OPREF=$(printf '%s%s' 'op://Private/' 'op-service-account-ops')
HOSTLOCAL=$(printf '%s%s' 'tieubao' '.local')

PATTERN="${HOST}|${USR}|${OPREF}|${HOSTLOCAL}"

fail=0

# 1. Framework docs MUST be empty of personal markers.
echo "[1/2] Framework docs (must be placeholder-clean):"
for doc in "${FRAMEWORK_DOCS[@]}"; do
    if [[ ! -f "$doc" ]]; then
        echo "  ✗ $doc: missing"
        fail=1
        continue
    fi
    if matches=$(grep -nE "$PATTERN" "$doc" 2>/dev/null); then
        echo "  ✗ $doc: leaked personal context"
        if [[ "$VERBOSE" -eq 1 ]]; then
            while IFS= read -r line; do
                echo "      $line"
            done <<<"$matches"
        else
            echo "      (re-run with --verbose to see lines)"
        fi
        fail=1
    else
        echo "  ✓ $doc"
    fi
done

# 2. Operations cookbooks MUST contain personal markers (otherwise they're
#    not actually documenting an applied use of the pattern).
echo
echo "[2/2] Operations cookbooks (must contain author's specifics):"
for doc in "${OPERATIONS_DOCS[@]}"; do
    if [[ ! -f "$doc" ]]; then
        echo "  ✗ $doc: missing"
        fail=1
        continue
    fi
    if grep -qE "$PATTERN" "$doc" 2>/dev/null; then
        echo "  ✓ $doc (contains author's specifics, as expected)"
    else
        echo "  ✗ $doc: suspiciously placeholder-clean for an operations doc"
        fail=1
    fi
done

echo
if [[ "$fail" -eq 0 ]]; then
    echo "✓ Doc discipline contract holds."
    exit 0
else
    echo "✗ Doc discipline contract violated. See above."
    exit 1
fi
