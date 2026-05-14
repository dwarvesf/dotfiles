function mylaunchd --description 'List my user-level launchd jobs (no sudo). Use mylaunchd-all for system daemons too.'
    set -l filter 'mini\.|foundation\.d\.|truonghan'
    launchctl list | grep -E $filter
end
