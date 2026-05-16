# List BTM (Background Task Manager) login items grouped under a given
# developer name. Drills into the grouped row that System Settings shows
# under "Login Items & Extensions" without needing the GUI.
#
# Usage:
#   btm-list-dev                          # show items signed by "Dwarves Foundation"
#   btm-list-dev "AgileBits Inc."         # show items signed by another developer
#   btm-list-dev mini                     # local Mini (default is mini-tieubao SSH)
#   btm-list-dev mini "Dwarves Foundation"
#
# Backed by `sfltool dumpbtm` over SSH to the Mini. Requires passwordless
# sudo on that host (Han's mini-tieubao account has it).
function btm-list-dev --description "List BTM items grouped under a developer name (drills the System Settings grouped row)"
    set -l dev "Dwarves Foundation"
    set -l host mini-tieubao

    # Parse args: if first arg is "mini" / "air" / a known SSH alias, take it as host
    if test (count $argv) -ge 1
        switch $argv[1]
            case mini mini-tieubao mac-mini-danang air mac-air localhost
                set host $argv[1]
                if test (count $argv) -ge 2
                    set dev "$argv[2..-1]"
                end
            case '*'
                set dev "$argv[1..-1]"
        end
    end

    set -l cmd "sudo -n sfltool dumpbtm 2>/dev/null"

    if test "$host" = localhost
        eval $cmd
    else
        ssh $host $cmd
    end | grep -B1 -A8 "Developer Name: $dev" \
        | grep -E "Name:|Identifier: 8\.|Executable Path:|Disposition:"
end
