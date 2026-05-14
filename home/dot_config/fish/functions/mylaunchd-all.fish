function mylaunchd-all --description 'List my launchd jobs in both user and system domains (requires sudo for system).'
    set -l filter 'mini\.|foundation\.d\.|truonghan'

    set_color --bold; echo "=== user (gui/"(id -u)") ==="; set_color normal
    launchctl list | grep -E $filter

    set_color --bold; echo "=== system ==="; set_color normal
    sudo launchctl list | grep -E $filter
end
