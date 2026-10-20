#!/bin/bash
# Removes IpBump:   sudo /Applications/IpBump.app/Contents/Resources/uninstall.sh
# It leaves three things as they are: your network settings (choose "Switch back to automatic (DHCP)" first if
# you want that back), your AI agents' configuration (press Disconnect for each first) and your IpBump settings
# in ~/Library/Application Support/IpBump.
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

HELPER=io.github.discoveruz.ipbump.helper
AGENT=io.github.discoveruz.ipbump

launchctl bootout "system/$HELPER" 2>/dev/null
for uid in $(ps -axo uid=,comm= | awk '$2 ~ /loginwindow$/ { print $1 }' | sort -u); do
    launchctl bootout "gui/$uid/$AGENT" 2>/dev/null
done
pkill -f '^/Applications/IpBump.app/Contents/MacOS/IpBump$'

rm -f "/Library/LaunchDaemons/$HELPER.plist" "/Library/LaunchAgents/$AGENT.plist" \
      "/Library/PrivilegedHelperTools/$HELPER" /var/run/io.github.discoveruz.ipbump.v1.sock
rm -rf /Applications/IpBump.app
for id in io.github.discoveruz.ipbump.app io.github.discoveruz.ipbump.helper; do pkgutil --forget "$id" >/dev/null 2>&1; done
echo "IpBump is removed."
