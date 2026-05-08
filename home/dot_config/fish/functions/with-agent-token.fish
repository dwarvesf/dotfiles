function with-agent-token --description 'Run cmd with OP_SERVICE_ACCOUNT_TOKEN injected (S-47)'
    # Update this ref if the service-account 1P item changes.
    set -l ref "op://Private/op-service-account-ops/credential"

    if test (count $argv) -eq 0
        echo "Usage: with-agent-token <command> [args...]" >&2
        echo "" >&2
        echo "  Injects OP_SERVICE_ACCOUNT_TOKEN into the wrapped process only." >&2
        echo "  Daily shell stays biometric / full-vault. See docs/specs/S-47." >&2
        return 2
    end

    set -l token ($HOME/.local/bin/secret-cache-read OP_SERVICE_ACCOUNT_TOKEN $ref)
    if test -z "$token"
        echo "with-agent-token: could not fetch $ref (op signed in?)" >&2
        return 1
    end

    OP_SERVICE_ACCOUNT_TOKEN=$token $argv
end
