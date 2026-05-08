function dotfiles -d "Manage dotfiles via chezmoi"
    switch $argv[1]
        case edit e
            if test (count $argv) -lt 2
                echo "Usage: dotfiles edit <path> [--no-commit]"
                echo "  Edits the source, applies on save, auto-commits the diff."
                return 1
            end

            set -l no_commit 0
            set -l paths
            for a in $argv[2..]
                switch $a
                    case --no-commit
                        set no_commit 1
                    case '*'
                        set -a paths $a
                end
            end

            chezmoi edit --apply $paths; or return 1

            if test $no_commit -eq 1
                return 0
            end

            set -l repo (dirname (chezmoi source-path))
            if not git -C $repo diff --quiet -- home/
                set -l changed (git -C $repo diff --name-only -- home/)
                if test (count $changed) -gt 0
                    git -C $repo add $changed
                    set -l summary (string join ", " (for p in $changed; basename $p; end))
                    git -C $repo commit -m "chore(config): update $summary via dotfiles edit" >/dev/null
                    echo "✓ committed: $summary"
                    echo "  push with: git -C $repo push"
                end
            end

        case drift
            set -l no_commit 0
            contains -- --no-commit $argv; and set no_commit 1

            set -l drifted (chezmoi status 2>/dev/null | string match -r '^ M\s+(.+)$' | string replace -r '^ M\s+' '')
            set -l paths
            set -l i 2
            while test $i -le (count $drifted)
                set -a paths $drifted[$i]
                set i (math $i + 2)
            end

            if test (count $paths) -eq 0
                echo "✓ no drift  - deployed files match source"
                return 0
            end

            echo "Drifted files (deployed ≠ source):"
            for p in $paths
                echo "  $p"
            end
            echo ""
            echo "Run 'chezmoi diff $paths[1]' to preview; 'dotfiles drift' will re-absorb all of them."
            read -P "Re-absorb into source? [y/N] " ans
            if not string match -qri '^y' -- $ans
                echo "aborted"
                return 1
            end

            chezmoi re-add $paths; or return 1
            echo "✓ source updated"

            if test $no_commit -eq 1
                return 0
            end

            set -l repo (dirname (chezmoi source-path))
            if not git -C $repo diff --quiet -- home/
                set -l changed (git -C $repo diff --name-only -- home/)
                git -C $repo add $changed
                set -l summary (string join ", " (for p in $changed; basename $p; end))
                git -C $repo commit -m "chore(config): sync drift from machine ($summary)" >/dev/null
                echo "✓ committed. Push with: git -C $repo push"
            end

        case secret
            switch $argv[2]
                case add
                    if test (count $argv) -lt 4
                        echo "Usage: dotfiles secret add VAR_NAME \"op://Vault/Item/field\" [--no-commit]"
                        echo "Example: dotfiles secret add OPENAI_API_KEY \"op://Private/OpenAI/credential\""
                        echo ""
                        echo "If the 1Password item doesn't exist yet you'll be prompted for the"
                        echo "value and the item will be created automatically."
                        return 1
                    end

                    set -l var $argv[3]
                    set -l ref $argv[4]
                    set -l do_commit 1
                    contains -- --no-commit $argv; and set do_commit 0

                    if not string match -qr '^[A-Z_][A-Z0-9_]*$' -- $var
                        echo "✗ VAR_NAME must be UPPER_SNAKE_CASE, got: $var"
                        return 1
                    end

                    set -l parts (string split / -- (string replace 'op://' '' -- $ref))
                    if test (count $parts) -lt 3
                        echo "✗ reference must be op://Vault/Item/field , got: $ref"
                        return 1
                    end
                    set -l op_vault $parts[1]
                    set -l op_field $parts[-1]
                    set -l op_item (string join / $parts[2..-2])

                    if not op read "$ref" >/dev/null 2>&1
                        echo "No item found at $ref  - creating it now."
                        if not op account list >/dev/null 2>&1
                            echo "✗ 1Password CLI is not signed in. Run: eval (op signin)"
                            return 1
                        end
                        read -s -P "Enter value for $var: " value
                        echo ""
                        if test -z "$value"
                            echo "✗ empty value, aborting"
                            return 1
                        end
                        if not op item create --vault="$op_vault" --category="API Credential" \
                                --title="$op_item" "$op_field=$value" >/dev/null 2>&1
                            echo "✗ op item create failed (vault=$op_vault title=$op_item)"
                            return 1
                        end
                        echo "✓ created 1Password item: $op_item"
                        if not op read "$ref" >/dev/null 2>&1
                            echo "✗ item created but $ref still unreadable; check field name"
                            return 1
                        end
                    end

                    set -l data (chezmoi source-path)/.chezmoidata/secrets.toml
                    if test ! -f $data
                        echo "✗ $data missing; dotfiles may need reinstall"
                        return 1
                    end

                    if grep -q "^$var = " $data
                        echo "⚠ $var already registered; use 'dotfiles secret rm' first to replace"
                        return 1
                    end

                    printf '%s = "%s"\n' "$var" "$ref" >> $data
                    echo "✓ added $var → $ref"

                    # S-48: scope apply to secrets.fish so unrelated drift in
                    # other managed files cannot abort the apply mid-stream
                    # after secrets.fish has already been re-rendered.
                    set -l target $HOME/.config/fish/conf.d/secrets.fish
                    echo "→ chezmoi apply $target"
                    chezmoi apply $target; or begin
                        echo "✗ chezmoi apply failed; reverting registry + target"
                        sed -i '' "/^$var = /d" $data
                        chezmoi apply $target >/dev/null 2>&1
                        return 1
                    end

                    echo "✓ applied. Open a new shell (or `exec fish`) to load \$$var."

                    set -l repo (dirname (chezmoi source-path))
                    if test $do_commit -eq 1
                        git -C $repo add .chezmoidata/secrets.toml
                        git -C $repo commit -m "feat(secrets): register $var" >/dev/null
                        echo "✓ committed. Push with: git -C $repo push"
                    else
                        echo "Commit: git -C $repo add .chezmoidata/secrets.toml && git commit -m 'feat(secrets): register $var'"
                    end

                case rm
                    if test (count $argv) -lt 3
                        echo "Usage: dotfiles secret rm VAR_NAME [--no-commit]"
                        return 1
                    end

                    set -l var $argv[3]
                    set -l do_commit 1
                    contains -- --no-commit $argv; and set do_commit 0

                    set -l data (chezmoi source-path)/.chezmoidata/secrets.toml
                    if not grep -q "^$var = " $data
                        echo "⚠ $var not registered"
                        return 1
                    end

                    sed -i '' "/^$var = /d" $data
                    echo "✓ removed $var"

                    # S-48: scope apply to secrets.fish only.
                    set -l target $HOME/.config/fish/conf.d/secrets.fish
                    echo "→ chezmoi apply $target"
                    chezmoi apply $target; or return 1
                    echo "✓ applied. \$$var will be absent from new shells."

                    if test $do_commit -eq 1
                        set -l repo (dirname (chezmoi source-path))
                        git -C $repo add .chezmoidata/secrets.toml
                        git -C $repo commit -m "chore(secrets): unregister $var" >/dev/null
                        echo "✓ committed."
                    end

                case list ls
                    set -l data (chezmoi source-path)/.chezmoidata/secrets.toml
                    if test ! -f $data
                        echo "(no secrets registered)"
                        return 0
                    end
                    echo "Registered secrets (cache status from macOS Keychain):"
                    for line in (grep -E '^[A-Z_][A-Z0-9_]* = ' $data)
                        set -l var (echo $line | awk '{print $1}')
                        set -l ref (echo $line | sed 's/.*= //;s/"//g')
                        if security find-generic-password -a "$USER" -s "$var" -w >/dev/null 2>&1
                            echo "  [cached] $var → $ref"
                        else
                            echo "  [ empty] $var → $ref"
                        end
                    end

                case refresh
                    # Delete Keychain entry so next shell (or immediate call) re-fetches from 1Password.
                    set -l data (chezmoi source-path)/.chezmoidata/secrets.toml
                    set -l do_all 0
                    contains -- --all $argv; and set do_all 1

                    if test $do_all -eq 1
                        for var in (grep -E '^[A-Z_][A-Z0-9_]* = ' $data | awk '{print $1}')
                            security delete-generic-password -a "$USER" -s "$var" >/dev/null 2>&1
                            echo "✓ cleared cache: $var"
                        end
                        echo ""
                        echo "Run 'exec fish' (or open a new shell) to re-populate from 1Password."
                        return 0
                    end

                    if test (count $argv) -lt 3
                        echo "Usage: dotfiles secret refresh <VAR>"
                        echo "       dotfiles secret refresh --all"
                        echo ""
                        echo "  Clears the Keychain cache so the secret is re-fetched from 1Password"
                        echo "  on next shell startup (or next access)."
                        return 1
                    end

                    set -l var $argv[3]
                    if not grep -q "^$var = " $data
                        echo "✗ $var not registered (see 'dotfiles secret list')"
                        return 1
                    end

                    security delete-generic-password -a "$USER" -s "$var" >/dev/null 2>&1
                    echo "✓ cleared cache: $var"

                    # Immediately re-populate (triggers 1P popup once).
                    # Do NOT echo $val: the hint used to print it, which leaked
                    # values into terminal scrollback and transcripts. See S-45.
                    set -l ref (grep "^$var = " $data | sed 's/.*= //;s/"//g')
                    set -l val ($HOME/.local/bin/secret-cache-read "$var" "$ref")
                    if test -n "$val"
                        echo "✓ re-fetched from 1Password and cached in Keychain."
                        echo "  Open a new shell (or run 'exec fish') to load the new value into \$$var."
                    else
                        echo "⚠ could not fetch from 1Password (op not signed in?)"
                    end

                case push
                    # S-51: seed a remote machine's Keychain with a registered secret's
                    # value, without requiring biometric on the remote. Read locally via
                    # `op read` (uses your biometric session on this machine), pipe over
                    # SSH, write to the remote login keychain via security(1). Idempotent.
                    if test (count $argv) -lt 4
                        echo "Usage: dotfiles secret push VAR_NAME ssh-target"
                        echo "Example: dotfiles secret push OP_SERVICE_ACCOUNT_TOKEN remote-host"
                        echo ""
                        echo "  Reads the value from 1Password locally (biometric), pipes over SSH,"
                        echo "  and writes to the remote user's login keychain. The value never"
                        echo "  appears on the remote command line or in shell history."
                        echo "  Re-run after a token rotation to update the remote cache."
                        return 1
                    end

                    set -l var $argv[3]
                    set -l ssh_target $argv[4]

                    set -l data (chezmoi source-path)/.chezmoidata/secrets.toml
                    if not grep -q "^$var = " $data
                        echo "✗ $var not registered (see 'dotfiles secret list')"
                        return 1
                    end

                    set -l ref (grep "^$var = " $data | sed 's/.*= //;s/"//g')

                    # Force biometric path. Subprocess fish (e.g. invoked from a non-fish
                    # parent shell) doesn't trigger the S-49 interactive-only interceptor,
                    # so `op read` would default to bearer auth and fail to read items
                    # outside the SA's vault scope. The `op://Private/op-service-account-*`
                    # ref is the canonical example: SA cannot read its own credential by
                    # design (S-46 defense in depth). Drop the token explicitly so this
                    # helper always uses the user's full-vault biometric session.
                    set -l val (env -u OP_SERVICE_ACCOUNT_TOKEN op read "$ref" 2>/dev/null)
                    if test -z "$val"
                        echo "✗ op read $ref returned empty (not signed in, wrong ref, or network)"
                        echo "  Try: eval (op signin) then re-run."
                        return 1
                    end

                    # Probe the SSH target before piping the value, so a typo doesn't
                    # send the secret into a void.
                    if not ssh -o BatchMode=yes -o ConnectTimeout=5 $ssh_target true 2>/dev/null
                        echo "✗ cannot reach $ssh_target via SSH (key auth or hostname issue)"
                        return 1
                    end

                    # Remote command: invoke bash explicitly so $(cat) works regardless
                    # of the remote user's login shell. Stdin carries the value. -A is
                    # required so the entry is readable from any user-owned process
                    # (GUI fish OR SSH-originated fish), matching `secret-cache-read`'s
                    # caching ACL. See S-51 multi-machine doc for why.
                    set -l write_cmd "bash -c 'security add-generic-password -a \"\$USER\" -s \"$var\" -w \"\$(cat)\" -A -U 2>&1'"
                    set -l write_out (echo -n $val | ssh $ssh_target $write_cmd 2>&1)

                    # Verify by reading back: the prefix of the value should match what
                    # we sent. Avoids relying on the remote command's exit propagation
                    # through the SSH login-shell wrapper (which is unreliable for
                    # bash -c invocations under a fish login shell).
                    set -l read_cmd "bash -c 'security find-generic-password -a \"\$USER\" -s \"$var\" -w 2>/dev/null | head -c 4'"
                    set -l read_back (ssh $ssh_target $read_cmd 2>/dev/null)
                    set -l expected_prefix (string sub -l 4 -- $val)

                    if test "$read_back" = "$expected_prefix"
                        echo "✓ Seeded $var on $ssh_target. (verified by read-back)"
                    else
                        echo "✗ remote keychain write failed."
                        if string match -q "*Write permissions error*" -- "$write_out"; or string match -q "*User interaction is not allowed*" -- "$write_out"
                            echo "  Cause: the remote login keychain is locked, and SSH key-auth"
                            echo "  sessions cannot show the unlock dialog."
                            echo ""
                            echo "  Fix one of:"
                            echo "    1. Walk to $ssh_target and log in at the screen (one-time per reboot)."
                            echo "    2. Enable auto-login for the user (System Settings → Users & Groups)."
                            echo "    3. Run from a session that already lives inside the remote GUI"
                            echo "       login (e.g. tmux attach into a console-launched session)."
                            echo "  See docs/1password-multi-machine.md for details."
                        else
                            echo "  Remote output:"
                            for line in (string split \n -- $write_out)
                                echo "    $line"
                            end
                        end
                        return 1
                    end

                case ''
                    echo "Usage: dotfiles secret <add|rm|list|refresh|push>"
                    echo ""
                    echo "  add VAR \"op://...\"     Register a secret"
                    echo "  rm VAR                 Unregister a secret"
                    echo "  list                   Show all bindings (with cache status)"
                    echo "  refresh VAR            Clear Keychain cache, re-fetch from 1Password"
                    echo "  refresh --all          Refresh all cached secrets"
                    echo "  push VAR ssh-target    Seed a remote machine's Keychain (S-51)"

                case '*'
                    echo "Unknown secret command: $argv[2]"
                    echo "Usage: dotfiles secret <add|rm|list|refresh|push>"
                    return 1
            end

        case local
            set -l brewlocal $HOME/.Brewfile.local
            set -l extlocal $HOME/.config/code/extensions.local.txt
            set -l fishlocal $HOME/.config/fish/config.local.fish
            set -l tmuxlocal $HOME/.config/tmux/tmux.local.conf
            set -l gitlocal $HOME/.gitconfig.local
            set -l repo (dirname (chezmoi source-path))
            set -l brewtmpl $repo/home/dot_Brewfile.tmpl
            set -l exttxt $repo/home/dot_config/code/extensions.txt

            switch $argv[2]
                case list ls ''
                    echo "Local overrides (machine-specific, not committed)"
                    echo "================================================="

                    echo ""
                    echo "~/.Brewfile.local"
                    if test -f $brewlocal
                        grep -E '^(brew|cask) "' $brewlocal | sed 's/^/  /' || echo "  (empty)"
                    else
                        echo "  (not created)"
                    end

                    echo ""
                    echo "~/.config/code/extensions.local.txt"
                    if test -f $extlocal
                        sed 's/^/  /' $extlocal
                    else
                        echo "  (not created)"
                    end

                    echo ""
                    echo "~/.config/fish/config.local.fish"
                    if test -f $fishlocal
                        echo "  ($(wc -l < $fishlocal | string trim) lines)"
                    else
                        echo "  (not created)"
                    end

                    echo ""
                    echo "~/.config/tmux/tmux.local.conf"
                    if test -f $tmuxlocal
                        echo "  ($(wc -l < $tmuxlocal | string trim) lines)"
                    else
                        echo "  (not created)"
                    end

                    echo ""
                    echo "~/.gitconfig.local"
                    if test -f $gitlocal
                        echo "  ($(wc -l < $gitlocal | string trim) lines)"
                    else
                        echo "  (not created)"
                    end

                case edit
                    if not test -f $brewlocal
                        printf '%s\n' \
                            '# ~/.Brewfile.local - machine-specific packages (not committed)' \
                            '# Sourced automatically by ~/.Brewfile via eval()' \
                            '' > $brewlocal
                    end
                    $EDITOR $brewlocal

                case promote
                    if test (count $argv) -lt 4
                        echo "Usage: dotfiles local promote <brew|cask|ext> <name>"
                        echo "  Moves an item from a .local file to the shared repo."
                        return 1
                    end
                    set -l type $argv[3]
                    set -l name $argv[4]

                    switch $type
                        case brew cask
                            if not test -f $brewlocal
                                echo "✗ ~/.Brewfile.local does not exist"
                                return 1
                            end
                            if not grep -qE "^$type \"$name\"" $brewlocal
                                echo "✗ $type \"$name\" not found in ~/.Brewfile.local"
                                return 1
                            end
                            # Extract full line (with comment) before deleting
                            set -l line (grep -E "^$type \"$name\"" $brewlocal | head -1)
                            # Remove from local
                            sed -i '' "/^$type \"$name\"/d" $brewlocal
                            # Insert in core before the local-overrides anchor
                            set -l anchor '# ── Local overrides'
                            if not grep -qF "$anchor" $brewtmpl
                                echo "✗ anchor not found in $brewtmpl; aborting"
                                # Restore local entry
                                echo $line >> $brewlocal
                                return 1
                            end
                            # Use awk to insert before the anchor line
                            awk -v line="$line" -v anchor="$anchor" '
                                index($0, anchor) && !inserted {
                                    print line "  # promoted from local"
                                    print ""
                                    inserted = 1
                                }
                                { print }
                            ' $brewtmpl > $brewtmpl.tmp && mv $brewtmpl.tmp $brewtmpl
                            echo "✓ promoted $type \"$name\" to core Brewfile"

                        case ext
                            if not test -f $extlocal
                                echo "✗ ~/.config/code/extensions.local.txt does not exist"
                                return 1
                            end
                            if not grep -qxF "$name" $extlocal
                                echo "✗ \"$name\" not found in extensions.local.txt"
                                return 1
                            end
                            sed -i '' "/^$name\$/d" $extlocal
                            echo "$name" >> $exttxt
                            # Re-sort extensions.txt to keep it alphabetical
                            sort -o $exttxt $exttxt
                            echo "✓ promoted extension $name to core"

                        case '*'
                            echo "Unknown type: $type (expected: brew, cask, ext)"
                            return 1
                    end

                    # chezmoi apply + commit
                    chezmoi apply; or return 1
                    if not git -C $repo diff --quiet -- home/
                        git -C $repo add home/
                        git -C $repo commit -m "feat(core): promote $type $name from local" >/dev/null
                        echo "✓ committed. Push with: git -C $repo push"
                    end

                case demote
                    if test (count $argv) -lt 4
                        echo "Usage: dotfiles local demote <brew|cask|ext> <name>"
                        echo "  Moves an item from the shared repo to a .local file."
                        return 1
                    end
                    set -l type $argv[3]
                    set -l name $argv[4]

                    switch $type
                        case brew cask
                            if not grep -qE "^$type \"$name\"" $brewtmpl
                                echo "✗ $type \"$name\" not found in dot_Brewfile.tmpl"
                                return 1
                            end
                            # Extract and remove line from template
                            set -l line (grep -E "^$type \"$name\"" $brewtmpl | head -1 | sed 's/  # promoted from local//')
                            sed -i '' "/^$type \"$name\"/d" $brewtmpl
                            # Ensure local file exists with header
                            if not test -f $brewlocal
                                printf '%s\n' \
                                    '# ~/.Brewfile.local - machine-specific packages (not committed)' \
                                    '# Sourced automatically by ~/.Brewfile via eval()' \
                                    '' > $brewlocal
                            end
                            echo $line >> $brewlocal
                            echo "✓ demoted $type \"$name\" to ~/.Brewfile.local"

                        case ext
                            if not grep -qxF "$name" $exttxt
                                echo "✗ \"$name\" not found in extensions.txt"
                                return 1
                            end
                            sed -i '' "/^$name\$/d" $exttxt
                            echo "$name" >> $extlocal
                            echo "✓ demoted extension $name to extensions.local.txt"

                        case '*'
                            echo "Unknown type: $type (expected: brew, cask, ext)"
                            return 1
                    end

                    # chezmoi apply + commit repo changes
                    chezmoi apply; or return 1
                    if not git -C $repo diff --quiet -- home/
                        git -C $repo add home/
                        git -C $repo commit -m "chore(local): demote $type $name to local" >/dev/null
                        echo "✓ committed. Push with: git -C $repo push"
                    end

                case '*'
                    echo "Usage: dotfiles local <list|promote|demote|edit>"
                    echo ""
                    echo "  list                       Show all local overrides"
                    echo "  promote <type> <name>      Move local → core (repo)"
                    echo "  demote <type> <name>       Move core → local"
                    echo "  edit                       Open ~/.Brewfile.local in \$EDITOR"
                    echo ""
                    echo "  <type>: brew, cask, ext"
                    echo ""
                    echo "Examples:"
                    echo "  dotfiles local list"
                    echo "  dotfiles local promote cask chrysalis"
                    echo "  dotfiles local demote brew sentencepiece"
                    echo "  dotfiles local promote ext openai.chatgpt"
                    return 1
            end

        case diff d
            chezmoi diff --no-pager
        case sync s
            chezmoi apply
            and echo "Applied."
        case status st
            echo "Managed files:"
            chezmoi managed | wc -l
            echo ""
            echo "Pending changes:"
            chezmoi diff --no-pager | head -30
        case cd
            cd (chezmoi source-path)
        case refresh r
            chezmoi apply --refresh-externals
        case add a
            chezmoi add $argv[2..]
        case doctor
            set -l issues 0

            echo "Dotfiles health check"
            echo "====================="
            echo ""

            if command -q chezmoi
                echo "[ok] chezmoi installed"
            else
                echo "[!!] chezmoi not installed"
                set issues (math $issues + 1)
            end

            if test -L ~/.local/share/chezmoi
                echo "[ok] chezmoi source linked"
            else
                echo "[!!] chezmoi source not symlinked"
                set issues (math $issues + 1)
            end

            # Check the authoritative login shell from Directory Services, not $SHELL
            # ($SHELL is inherited from the parent process and goes stale after chsh)
            set -l login_shell (dscl . -read /Users/$USER UserShell 2>/dev/null | string replace 'UserShell: ' '')
            if test -z "$login_shell"
                set login_shell $SHELL  # fallback for non-macOS
            end
            if string match -q "*/fish" $login_shell
                echo "[ok] fish is default shell ($login_shell)"
            else
                echo "[!!] default shell is $login_shell (not fish)"
                set issues (math $issues + 1)
            end

            if command -q brew
                echo "[ok] homebrew installed"
            else
                echo "[!!] homebrew not found"
                set issues (math $issues + 1)
            end

            if command -q op
                if op account list &>/dev/null
                    echo "[ok] 1Password CLI: signed in"
                else
                    echo "[--] 1Password CLI: installed but not signed in"
                end
            else
                echo "[--] 1Password CLI: not installed (optional)"
            end

            if test -e "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
                echo "[ok] 1Password SSH agent: socket exists"
            else
                echo "[--] 1Password SSH agent: not found (optional)"
            end

            if not command -q op
                echo "[--] SSH key backup status: op CLI not available (optional)"
            else if not op account list &>/dev/null
                echo "[--] SSH key backup status: op not signed in (run: op signin)"
            else
                set -l audit_out (dotfiles ssh audit 2>/dev/null)
                set -l none_line (echo $audit_out | grep -oE 'no disk keys to back up' | head -1)
                set -l all_ok_line (echo $audit_out | grep -oE 'all [0-9]+ disk key\(s\) have a 1P counterpart' | head -1)
                set -l gap_line (echo $audit_out | grep -oE '[0-9]+ of [0-9]+ disk key\(s\) have no 1P backup' | head -1)
                if test -n "$none_line"
                    echo "[ok] SSH keys: none on disk (any in-use keys served by 1P agent)"
                else if test -n "$all_ok_line"
                    set -l n (echo $all_ok_line | awk '{print $2}')
                    echo "[ok] SSH keys: $n on disk, all backed up to 1P"
                else if test -n "$gap_line"
                    set -l m (echo $gap_line | awk '{print $1}')
                    set -l n (echo $gap_line | awk '{print $3}')
                    echo "[!!] SSH keys: $m of $n disk key(s) lack 1P backup (run: dotfiles ssh adopt)"
                    set issues (math $issues + 1)
                else
                    echo "[--] SSH key backup status: audit produced no summary"
                end
            end

            # Surface any registered secret with no Keychain entry yet (S-43).
            # Informational: a fresh machine legitimately starts with an empty cache
            # until the first interactive fish login triggers secret-cache-read.
            set -l secrets_data (chezmoi source-path 2>/dev/null)/.chezmoidata/secrets.toml
            if test -f $secrets_data
                set -l empty_vars
                for line in (grep -E '^[A-Z_][A-Z0-9_]* = ' $secrets_data)
                    set -l var (echo $line | awk '{print $1}')
                    if not security find-generic-password -a "$USER" -s "$var" -w >/dev/null 2>&1
                        set -a empty_vars $var
                    end
                end
                if test (count $empty_vars) -eq 0
                    echo "[ok] all registered secrets cached in Keychain"
                else
                    echo "[--] registered but not cached: "(string join ", " $empty_vars)
                    echo "     (first interactive shell triggers 1P popup; or run 'exec fish')"
                end
            end

            for f in ~/.gitconfig ~/.config/fish/config.fish ~/.ssh/config
                if test -f $f
                    echo "[ok] $f exists"
                else
                    echo "[!!] $f missing"
                    set issues (math $issues + 1)
                end
            end

            set -l git_name (git config --global user.name 2>/dev/null)
            if test -n "$git_name"
                echo "[ok] git identity: $git_name <"(git config --global user.email)">"
            else
                echo "[!!] git identity not configured"
                set issues (math $issues + 1)
            end

            for tool in fzf bat eza zoxide delta mise starship
                if command -q $tool
                    echo "[ok] $tool"
                else
                    echo "[!!] $tool not found (run: brew bundle)"
                    set issues (math $issues + 1)
                end
            end

            if test -f ~/.config/chezmoi/key.txt
                echo "[ok] age encryption key exists"
            else
                echo "[--] age encryption key: not set up (optional)"
            end

            # Count real drift: exclude " R " (always-run scripts, not actual file changes)
            set -l drift_count (chezmoi status 2>/dev/null | grep -vcE '^ R ' | string trim)
            if test "$drift_count" -gt 0
                echo "[!!] $drift_count file(s) have drifted from source"
                set issues (math $issues + 1)
            else
                echo "[ok] no drift detected"
            end

            # ── .local pattern integrity ──────────────────────────────
            if chezmoi managed 2>/dev/null | grep -qE '(Brewfile\.local|\.local\.fish|tmux\.local\.conf|gitconfig\.local|extensions\.local\.txt)'
                echo "[!!] .local files are being tracked by chezmoi (should be ignored)"
                set issues (math $issues + 1)
            else
                echo "[ok] .local files correctly excluded from chezmoi"
            end

            if test -f ~/.Brewfile.local
                if ruby -c ~/.Brewfile.local >/dev/null 2>&1
                    echo "[ok] ~/.Brewfile.local is valid Ruby"
                else
                    echo "[!!] ~/.Brewfile.local has syntax errors"
                    set issues (math $issues + 1)
                end
            end

            set -l src (chezmoi source-path 2>/dev/null)
            if test -n "$src"
                set -l repo (dirname $src)
                set -l leaked (git -C $repo log --all --pretty=format: --name-only 2>/dev/null \
                    | grep -E '\.local($|\.|/)' | grep -v '^$' | sort -u)
                if test -n "$leaked"
                    echo "[!!] .local files found in git history:"
                    for f in $leaked
                        echo "     $f"
                    end
                    set issues (math $issues + 1)
                else
                    echo "[ok] no .local files leaked into git history"
                end
            end

            echo ""
            if test $issues -eq 0
                echo "All checks passed."
            else
                echo "$issues issue(s) found."
            end
            return $issues

        case encrypt-setup
            set -l key_path "$HOME/.config/chezmoi/key.txt"

            if test -f $key_path
                echo "Age key already exists at $key_path"
                echo "Public key:"
                grep "public key:" $key_path | string replace "# public key: " ""
                return 0
            end

            echo "Setting up age encryption for chezmoi..."
            echo ""

            if not command -q age-keygen
                echo "Installing age..."
                brew install age
            end

            mkdir -p (dirname $key_path)
            age-keygen -o $key_path 2>&1
            chmod 600 $key_path

            set -l pubkey (grep "public key:" $key_path | string replace "# public key: " "")
            echo ""
            echo "Public key: $pubkey"
            echo ""
            echo "Next steps:"
            echo "  1. Edit chezmoi config:"
            echo "     chezmoi edit-config"
            echo ""
            echo "  2. Add these lines:"
            echo "     encryption = \"age\""
            echo "     [age]"
            echo "     identity = \"$key_path\""
            echo "     recipient = \"$pubkey\""
            echo ""
            set -l vault (__dotfiles_op_vault)
            echo "  3. Back up the key to 1Password:"
            echo "     op document create $key_path --title 'chezmoi age key' --vault=$vault"
            echo ""
            echo "  4. Add encrypted files:"
            echo "     chezmoi add --encrypt ~/.kube/config"

        case update u
            set -l src (chezmoi source-path)
            if not test -d $src
                echo "chezmoi source not found"
                return 1
            end
            set -l repo (git -C $src rev-parse --show-toplevel 2>/dev/null)
            if test -z "$repo"
                echo "Not a git repo: $src"
                return 1
            end

            echo "==> Pulling latest..."
            git -C $repo pull --ff-only
            or begin
                echo "Pull failed. Resolve manually in $repo"
                return 1
            end

            echo "==> Applying..."
            chezmoi apply
            and echo "Updated and applied."

        case bench
            echo "Fish shell startup benchmark (10 runs):"
            echo ""
            set -l total 0
            for i in (seq 10)
                set -l start (perl -MTime::HiRes=time -e 'printf "%.0f\n", time*1000')
                fish -i -c exit 2>/dev/null
                set -l end (perl -MTime::HiRes=time -e 'printf "%.0f\n", time*1000')
                set -l ms (math "$end - $start")
                set total (math "$total + $ms")
                printf "  run %2d: %d ms\n" $i $ms
            end
            set -l avg (math "$total / 10")
            echo ""
            echo "Average: $avg ms"
            if test $avg -gt 500
                echo "Slow! (>500ms). Check config.fish for expensive init calls."
            else if test $avg -gt 200
                echo "Acceptable (200-500ms)."
            else
                echo "Fast (<200ms)."
            end

        case backup
            echo "Dotfiles backup"
            echo "==============="
            echo ""

            set -l config_path
            for ext in toml yaml json jsonnet
                if test -f "$HOME/.config/chezmoi/chezmoi.$ext"
                    set config_path "$HOME/.config/chezmoi/chezmoi.$ext"
                    break
                end
            end
            set -l key_path "$HOME/.config/chezmoi/key.txt"
            set -l vault (__dotfiles_op_vault)

            if test -z "$config_path"; or not test -f "$config_path"
                echo "[!!] chezmoi config not found"
                return 1
            end

            echo "[1/3] chezmoi config: $config_path"
            if command -q op
                echo "      Backing up to 1Password..."
                op document create "$config_path" --title "chezmoi config (dotfiles backup)" --vault="$vault" 2>/dev/null
                and echo "      [ok] Uploaded to 1Password"
                or echo "      [!!] Upload failed. Are you signed in? (op signin)"
            else
                echo "      [--] 1Password CLI not found, skipping"
            end

            echo ""
            echo "[2/3] age encryption key: $key_path"
            if test -f "$key_path"
                if command -q op
                    echo "      Backing up to 1Password..."
                    op document create "$key_path" --title "chezmoi age key (dotfiles backup)" --vault="$vault" 2>/dev/null
                    and echo "      [ok] Uploaded to 1Password"
                    or echo "      [!!] Upload failed"
                else
                    echo "      [--] 1Password CLI not found, skipping"
                end
            else
                echo "      [--] No age key (not set up)"
            end

            echo ""
            echo "[3/3] Local fallback: ~/dotfiles-backup/"
            mkdir -p ~/dotfiles-backup
            cp "$config_path" ~/dotfiles-backup/chezmoi.toml 2>/dev/null
            and echo "      [ok] chezmoi.toml copied"
            if test -f "$key_path"
                cp "$key_path" ~/dotfiles-backup/key.txt 2>/dev/null
                chmod 600 ~/dotfiles-backup/key.txt
                and echo "      [ok] key.txt copied (mode 600)"
            end
            echo ""
            echo "Done. Restore on a new machine:"
            echo "  mkdir -p ~/.config/chezmoi"
            echo "  cp ~/dotfiles-backup/chezmoi.toml ~/.config/chezmoi/"
            echo "  cp ~/dotfiles-backup/key.txt ~/.config/chezmoi/  # if using age"

        case ssh
            set -l sub $argv[2]
            switch $sub
                case audit
                    set -l vault_default (__dotfiles_op_vault)

                    echo "SSH key inventory"
                    echo "============================================================"
                    echo ""
                    echo "[1] On-disk keys in ~/.ssh/"
                    echo "-----------------------------------------------------------"
                    set -l disk_fps
                    set -l disk_count 0
                    for f in (find ~/.ssh -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' 2>/dev/null)
                        set disk_count (math $disk_count + 1)
                        set -l pubfile "$f.pub"
                        set -l fp "?"
                        set -l ktype "?"
                        set -l bits "?"
                        if test -f $pubfile
                            set -l info (ssh-keygen -lf $pubfile 2>/dev/null)
                            if test -n "$info"
                                set bits (echo $info | awk '{print $1}')
                                set fp (echo $info | awk '{print $2}')
                                set ktype (echo $info | awk '{print $NF}' | tr -d '()')
                            end
                        end

                        set -l pp "unknown"
                        if test -r $f
                            if ssh-keygen -y -P "" -f $f >/dev/null 2>&1
                                set pp "none"
                            else
                                set pp "set"
                            end
                        end

                        set -l mtime (stat -f %m $f 2>/dev/null); or set mtime 0
                        set -l age_sec 0
                        test $mtime -gt 0; and set age_sec (math (date +%s) - $mtime)
                        set -l age_str "-"
                        if test $age_sec -gt 31536000
                            set age_str (math -s0 $age_sec / 31536000)"y"
                        else if test $age_sec -gt 2592000
                            set age_str (math -s0 $age_sec / 2592000)"mo"
                        else if test $age_sec -gt 86400
                            set age_str (math -s0 $age_sec / 86400)"d"
                        else if test $age_sec -gt 0
                            set age_str "<1d"
                        end

                        set -l flags ""
                        if test "$ktype" = "RSA"; and test "$bits" != "?"
                            test $bits -lt 3072 2>/dev/null; and set flags "$flags weak"
                        end
                        test $age_sec -gt 157680000; and set flags "$flags old"
                        test "$pp" = "none"; and set flags "$flags plaintext"
                        test -n "$flags"; and set flags "⚠$flags"

                        test "$fp" != "?"; and set -a disk_fps $fp
                        set -l name (string replace "$HOME/.ssh/" "" $f)
                        printf "  %-32s  %-8s  pass=%-7s  age=%-6s  %s\n" $name "$ktype $bits" $pp $age_str $flags
                    end
                    test $disk_count -eq 0; and echo "  (none)"
                    echo ""

                    echo "[2] Keys in active SSH agent"
                    echo "-----------------------------------------------------------"
                    set -l agent_out (ssh-add -l 2>&1)
                    if string match -qi "*no identities*" -- "$agent_out"
                        echo "  (agent has no identities)"
                    else if string match -qi "*could not open*" -- "$agent_out"
                        echo "  (no agent running)"
                    else
                        for line in $agent_out
                            echo "  $line"
                        end
                    end
                    echo ""

                    echo "[3] SSH keys in 1Password (vault: $vault_default)"
                    echo "-----------------------------------------------------------"
                    # S-57: strip OP_SERVICE_ACCOUNT_TOKEN explicitly so the audit
                    # always queries via biometric (the user's full-vault scope).
                    # The S-49 op interceptor only strips the token when
                    # `status is-interactive` is true; this case is reached from
                    # non-interactive contexts (CC's Bash tool, scripts, cron) where
                    # the SA-scoped session can't see Private vault items.
                    set -l op_fps
                    if not command -q op
                        echo "  (op CLI not installed; skipping)"
                    else if not env -u OP_SERVICE_ACCOUNT_TOKEN command op account get >/dev/null 2>&1
                        echo "  (not signed in to 1Password; run: op signin)"
                    else
                        set -l items_json (env -u OP_SERVICE_ACCOUNT_TOKEN command op item list --categories "SSH Key" --vault $vault_default --format json 2>/dev/null)
                        if test -z "$items_json"; or test "$items_json" = "[]"
                            echo "  (no SSH Key items in vault)"
                        else
                            for id in (echo $items_json | jq -r '.[].id' 2>/dev/null)
                                set -l title (echo $items_json | jq -r ".[] | select(.id==\"$id\") | .title")
                                set -l pubkey (env -u OP_SERVICE_ACCOUNT_TOKEN command op item get $id --fields label="public key" --reveal 2>/dev/null)
                                set -l fp "?"
                                if test -n "$pubkey"
                                    set fp (echo $pubkey | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
                                    test -z "$fp"; and set fp "?"
                                end
                                test "$fp" != "?"; and set -a op_fps $fp
                                printf "  %-40s  fp=%s\n" $title $fp
                            end
                        end
                    end
                    echo ""

                    echo "[4] Backup status"
                    echo "-----------------------------------------------------------"
                    if test $disk_count -eq 0
                        echo "  (no disk keys to back up)"
                    else
                        set -l unbacked 0
                        for fp in $disk_fps
                            contains -- $fp $op_fps; or set unbacked (math $unbacked + 1)
                        end
                        if test $unbacked -eq 0
                            echo "  ✓ all $disk_count disk key(s) have a 1P counterpart"
                        else
                            echo "  ⚠ $unbacked of $disk_count disk key(s) have no 1P backup"
                            echo "    Run: dotfiles ssh adopt ~/.ssh/<name>"
                        end
                    end

                case adopt
                    set -l argc (count $argv)
                    if test $argc -lt 3
                        echo "Usage: dotfiles ssh adopt <key-path> [--title NAME] [--vault NAME]"
                        echo "  Guided flow: copies the private key to clipboard, opens 1Password"
                        echo "  desktop, waits for you to paste+save, then verifies by fingerprint."
                        echo "  1P CLI cannot import SSH keys, so this step is manual by necessity."
                        echo "  The on-disk file is never touched."
                        return 1
                    end

                    set -l keyfile $argv[3]
                    set -l title ""
                    set -l vault ""

                    set -l i 4
                    while test $i -le $argc
                        switch $argv[$i]
                            case --title
                                set i (math $i + 1)
                                set title $argv[$i]
                            case --vault
                                set i (math $i + 1)
                                set vault $argv[$i]
                            case '*'
                                echo "Unknown arg: $argv[$i]"
                                return 1
                        end
                        set i (math $i + 1)
                    end

                    if not test -f $keyfile
                        echo "✗ no such file: $keyfile"
                        return 1
                    end

                    if not command -q op
                        echo "✗ op CLI not installed. brew install 1password-cli"
                        return 1
                    end

                    if not op account get >/dev/null 2>&1
                        echo "✗ not signed in to 1Password. Run: op signin"
                        return 1
                    end

                    if test -z "$vault"
                        set vault (__dotfiles_op_vault)
                    end

                    set -l pubfile "$keyfile.pub"
                    set -l fp
                    if test -f $pubfile
                        set fp (ssh-keygen -lf $pubfile 2>/dev/null | awk '{print $2}')
                    else
                        set fp (ssh-keygen -y -P "" -f $keyfile 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
                    end
                    if test -z "$fp"
                        echo "✗ could not compute fingerprint for $keyfile"
                        echo "  (passphrase-protected keys must be decrypted before adoption)"
                        return 1
                    end

                    set -l items_json (op item list --categories "SSH Key" --vault $vault --format json 2>/dev/null)
                    if test -n "$items_json"; and test "$items_json" != "[]"
                        for id in (echo $items_json | jq -r '.[].id' 2>/dev/null)
                            set -l ep (op item get $id --fields label="public key" --reveal 2>/dev/null)
                            set -l efp (echo $ep | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
                            if test "$efp" = "$fp"
                                set -l etitle (echo $items_json | jq -r ".[] | select(.id==\"$id\") | .title")
                                echo "✓ already adopted: $etitle (fp: $fp)"
                                return 0
                            end
                        end
                    end

                    if test -z "$title"
                        set title "SSH - "(basename $keyfile)
                    end

                    echo "Guided adoption"
                    echo "==============="
                    echo "  1Password CLI (op 2.x) cannot import existing SSH private keys."
                    echo "  This command will: copy the key to your clipboard, open the"
                    echo "  1Password desktop app, wait for you to paste and save, then"
                    echo "  verify the import by fingerprint."
                    echo ""
                    echo "  Key:         $keyfile"
                    echo "  Fingerprint: $fp"
                    echo "  Suggested title: $title"
                    echo "  Target vault:    $vault"
                    echo ""
                    read -P "Proceed with guided adoption? [y/N] " ans
                    if not string match -qri '^y' -- $ans
                        echo "aborted"
                        return 1
                    end

                    if not command -q pbcopy
                        echo "✗ pbcopy not found (expected on macOS). aborting."
                        return 1
                    end

                    pbcopy < $keyfile
                    echo ""
                    echo "✓ Private key copied to clipboard."
                    open -a "1Password" 2>/dev/null
                    echo ""
                    echo "In 1Password desktop:"
                    echo "  1. New Item → category: 'SSH Key'"
                    echo "  2. Title: $title"
                    echo "  3. Paste into the 'private key' field (Cmd-V)"
                    echo "  4. Move item to vault: $vault"
                    echo "  5. Save"
                    echo ""
                    read -P "Press Enter after you've saved the item in 1Password... " _

                    printf "" | pbcopy
                    echo "(clipboard cleared)"
                    echo ""

                    set -l post_items (op item list --categories "SSH Key" --vault $vault --format json 2>/dev/null)
                    set -l found 0
                    if test -n "$post_items"; and test "$post_items" != "[]"
                        for id in (echo $post_items | jq -r '.[].id' 2>/dev/null)
                            set -l ipub (op item get $id --fields label="public key" --reveal 2>/dev/null)
                            set -l ifp (echo $ipub | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
                            if test "$ifp" = "$fp"
                                set -l ititle (echo $post_items | jq -r ".[] | select(.id==\"$id\") | .title")
                                echo "✓ Verified in 1P: '$ititle' (vault: $vault)"
                                echo "  Fingerprint: $fp"
                                echo ""
                                echo "  The disk copy at $keyfile is untouched."
                                echo "  When you are confident nothing needs the disk copy:"
                                echo "    mv $keyfile{,.pub} ~/.Trash/"
                                echo "  Re-run 'dotfiles ssh audit' to confirm 1P serves this key."
                                set found 1
                                break
                            end
                        end
                    end
                    if test $found -eq 0
                        echo "✗ Did not find a 1P SSH Key item with fingerprint $fp in vault '$vault'."
                        echo "  Possible causes:"
                        echo "    - Item not saved yet, or saved to a different vault"
                        echo "    - Private key content was altered during paste"
                        echo "    - 1P has not synced yet; wait a moment and re-run"
                        echo "  Run 'dotfiles ssh audit' to re-inventory."
                        return 1
                    end

                case backup
                    set -l argc (count $argv)
                    set -l dest ""

                    set -l i 3
                    while test $i -le $argc
                        switch $argv[$i]
                            case --destination -d
                                set i (math $i + 1)
                                set dest $argv[$i]
                            case '*'
                                echo "Unknown arg: $argv[$i]"
                                return 1
                        end
                        set i (math $i + 1)
                    end

                    if test -z "$dest"
                        echo "Usage: dotfiles ssh backup --destination <path>"
                        echo "  Writes an age-encrypted bundle: <path>/ssh-keys-<date>.age"
                        echo "  Requires: age, op (signed in), ~/.config/chezmoi/key.txt"
                        return 1
                    end

                    if not test -d $dest
                        echo "✗ destination not a directory: $dest"
                        return 1
                    end

                    if not command -q age
                        echo "✗ age not installed. brew install age"
                        return 1
                    end

                    if not command -q op
                        echo "✗ op CLI not installed. brew install 1password-cli"
                        return 1
                    end

                    if not op account get >/dev/null 2>&1
                        echo "✗ not signed in to 1Password. Run: op signin"
                        return 1
                    end

                    set -l age_key "$HOME/.config/chezmoi/key.txt"
                    if not test -f $age_key
                        echo "✗ no age identity found at $age_key"
                        echo "  Set one up first:"
                        echo "    age-keygen -o $age_key"
                        echo "    chmod 600 $age_key"
                        echo "  Then back it up to 1P:"
                        echo "    dotfiles backup"
                        return 1
                    end

                    set -l recipient (age-keygen -y $age_key 2>/dev/null)
                    if test -z "$recipient"
                        echo "✗ could not derive recipient from $age_key"
                        return 1
                    end

                    set -l vault (__dotfiles_op_vault)

                    set -l items_json (op item list --categories "SSH Key" --vault $vault --format json 2>/dev/null)
                    if test -z "$items_json"; or test "$items_json" = "[]"
                        echo "✗ no SSH Key items in vault '$vault' to back up"
                        return 1
                    end

                    set -l tempfile (mktemp -t ssh-bundle.XXXXXX)
                    chmod 600 $tempfile

                    echo "# ssh key bundle, generated "(date '+%Y-%m-%d %H:%M:%S')" by dotfiles ssh backup" > $tempfile
                    echo "# bundle format v1" >> $tempfile
                    echo "" >> $tempfile

                    set -l count 0
                    for id in (echo $items_json | jq -r '.[].id')
                        set -l title (echo $items_json | jq -r ".[] | select(.id==\"$id\") | .title")
                        set -l pub (op item get $id --fields label="public key" --reveal 2>/dev/null)
                        set -l priv (op item get $id --fields label="private key" --reveal 2>/dev/null | string collect)

                        if test -z "$priv"
                            echo "  ⚠ skipping '$title' (no private key field)"
                            continue
                        end

                        echo "=== BEGIN KEY: $title ===" >> $tempfile
                        echo "PUBLIC: $pub" >> $tempfile
                        echo "PRIVATE:" >> $tempfile
                        printf '%s\n' $priv >> $tempfile
                        echo "=== END KEY ===" >> $tempfile
                        echo "" >> $tempfile
                        set count (math $count + 1)
                    end

                    set -l outfile "$dest/ssh-keys-"(date +%F)".age"
                    age --encrypt --recipient $recipient --output $outfile $tempfile
                    set -l enc_status $status

                    rm -P $tempfile 2>/dev/null; or rm -f $tempfile

                    if test $enc_status -ne 0
                        echo "✗ age encryption failed"
                        return 1
                    end

                    set -l size (du -h $outfile 2>/dev/null | awk '{print $1}')
                    echo ""
                    echo "✓ Wrote $outfile"
                    echo "  Size: $size ($count keys)"
                    echo "  Recipient: $recipient"
                    echo ""
                    echo "  Restore on a new machine:"
                    echo "    age --decrypt -i $age_key $outfile"
                    echo "  Then create a new 1P SSH Key item in the desktop app and paste each"
                    echo "  === BEGIN KEY block's private key field. op CLI cannot import SSH keys."

                case '' '-h' '--help'
                    echo "Usage: dotfiles ssh <command>"
                    echo ""
                    echo "Commands:"
                    echo "  audit                                  Inventory: disk, agent, 1P, backup status"
                    echo "  adopt <key-path> [--title N] [--vault V]   Guided: clipboard+1P app+verify"
                    echo "  backup --destination <path>            Age-encrypted bundle to <path>"
                    return 1

                case '*'
                    echo "dotfiles ssh: unknown subcommand '$sub'"
                    echo "Run 'dotfiles ssh' for help."
                    return 1
            end

        case ''
            echo "Usage: dotfiles <command>"
            echo ""
            echo "Commands:"
            echo "  edit <file>       Edit + apply + auto-commit"
            echo "  drift             Detect and re-absorb drifted files"
            echo "  secret <cmd>      Manage 1Password secrets (add/rm/list)"
            echo "  local <cmd>       Manage machine-specific .local files (list/promote/demote/edit)"
            echo "  ssh <cmd>         SSH key inventory / adopt / backup (audit/adopt/backup)"
            echo "  diff              Show pending changes"
            echo "  sync              Apply all changes"
            echo "  update            Pull latest + apply"
            echo "  status            Show managed file count + pending diffs"
            echo "  cd                cd to chezmoi source directory"
            echo "  refresh           Re-download external files (fish plugins)"
            echo "  add <file>        Add a new file to chezmoi"
            echo "  doctor            Run health check on dotfiles setup"
            echo "  bench             Benchmark shell startup time"
            echo "  backup            Back up chezmoi config + age key"
            echo "  encrypt-setup     Set up age encryption"
        case '*'
            chezmoi $argv
    end
end
