#!/bin/sh
# Installs the latest IpBump for Mac from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/discoveruz/IpBump/main/mac/install.sh | sh
# A file curl downloads carries no quarantine flag, so macOS shows no "unidentified developer" warning;
# the installer asks for your password once. IPBUMP_PKG=<path to a .pkg> installs that file instead.
set -eu

major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 14 ]; then
    echo "IpBump needs macOS 14 or later."
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -n "${IPBUMP_PKG:-}" ]; then
    pkg=$IPBUMP_PKG
else
    url=$(curl -fsSL https://api.github.com/repos/discoveruz/IpBump/releases/latest \
        | grep -o '"browser_download_url": *"[^"]*\.pkg"' | head -n 1 | sed 's/.*"\(https[^"]*\)"$/\1/')
    if [ -z "$url" ]; then
        echo "No Mac installer in the latest release."
        exit 1
    fi
    echo "Downloading $url"
    curl -fL --progress-bar -o "$tmp/IpBump.pkg" "$url"
    curl -fsSL -o "$tmp/IpBump.pkg.sha256" "$url.sha256"
    expected=$(cut -d' ' -f1 < "$tmp/IpBump.pkg.sha256")
    actual=$(shasum -a 256 "$tmp/IpBump.pkg" | cut -d' ' -f1)
    if [ "$expected" != "$actual" ]; then
        echo "The download is damaged (its checksum does not match). Nothing was installed."
        exit 1
    fi
    pkg=$tmp/IpBump.pkg
fi

echo "Installing IpBump (macOS asks for your password)…"
sudo installer -pkg "$pkg" -target /
echo "Done. IpBump is in the menu bar."
