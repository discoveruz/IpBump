#!/bin/bash
# 1) build IpBump and its helper for Apple silicon and Intel   2) wrap them into IpBump.app and sign them
# 3) pack everything into dist/IpBump-<version>.pkg            (--app-only stops after step 2)
#
# The result is unsigned (ad hoc). With an Apple Developer ID, set these and macOS shows no warnings:
#   IPBUMP_SIGN_APP="Developer ID Application: <name> (<team>)"
#   IPBUMP_SIGN_INSTALLER="Developer ID Installer: <name> (<team>)"
#   IPBUMP_NOTARY_PROFILE=<a profile saved with: xcrun notarytool store-credentials>
set -euo pipefail
cd "$(dirname "$0")"

# The version is set in one place, IpBump/IpBump.csproj, for Windows and Mac alike
VERSION=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' ../IpBump/IpBump.csproj)
[ -n "$VERSION" ] || { echo "No <Version> found in ../IpBump/IpBump.csproj"; exit 1; }

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

# The licences of the open-source packages built in, as the Windows installer carries them too
notices() {
    echo "IpBump for Mac is built with the packages below. Their licences follow."
    for dir in .build/checkouts/*; do
        for file in "$dir"/LICENSE* "$dir"/NOTICE*; do
            [ -f "$file" ] || continue
            printf '\n==== %s: %s ====\n\n' "$(basename "$dir")" "$(basename "$file")"
            cat "$file"
        done
    done
}

sign() {   # <identifier> <path>
    if [ -n "${IPBUMP_SIGN_APP:-}" ]; then
        codesign --force --options runtime --timestamp --sign "$IPBUMP_SIGN_APP" --identifier "$1" "$2"
    else
        codesign --force --sign - --identifier "$1" "$2"   # ad hoc: Apple silicon runs nothing unsigned
    fi
}

rm -rf dist
APP=dist/IpBump.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/IpBump" "$APP/Contents/MacOS/IpBump"
sed "s/__VERSION__/$VERSION/g" Packaging/Info.plist > "$APP/Contents/Info.plist"
cp Assets/IpBump.icns Packaging/uninstall.sh "$APP/Contents/Resources/"
cp ../LICENSE "$APP/Contents/Resources/LICENSE.txt"
notices > "$APP/Contents/Resources/THIRD-PARTY-NOTICES.txt"
for bundle in "$BIN"/*.bundle; do [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"; done
cp "$BIN/ipbump-helper" dist/io.github.discoveruz.ipbump.helper
sign io.github.discoveruz.ipbump.helper dist/io.github.discoveruz.ipbump.helper
sign io.github.discoveruz.ipbump "$APP"

if [ "${1:-}" = "--app-only" ]; then
    echo "Done. The app is in mac/$APP"
    exit 0
fi

ROOT=dist/root
mkdir -p "$ROOT/Applications" "$ROOT/Library/PrivilegedHelperTools" "$ROOT/Library/LaunchDaemons" "$ROOT/Library/LaunchAgents"
cp -R "$APP" "$ROOT/Applications/"
cp dist/io.github.discoveruz.ipbump.helper "$ROOT/Library/PrivilegedHelperTools/"
cp Packaging/io.github.discoveruz.ipbump.helper.plist "$ROOT/Library/LaunchDaemons/"
cp Packaging/io.github.discoveruz.ipbump.plist "$ROOT/Library/LaunchAgents/"
chmod 755 "$ROOT/Library/PrivilegedHelperTools/io.github.discoveruz.ipbump.helper"
chmod 644 "$ROOT"/Library/LaunchDaemons/*.plist "$ROOT"/Library/LaunchAgents/*.plist

pkgbuild --root "$ROOT" --component-plist Packaging/component.plist --scripts Packaging/scripts \
    --identifier io.github.discoveruz.ipbump --version "$VERSION" --install-location / --ownership recommended \
    dist/IpBump-component.pkg
sed "s/__VERSION__/$VERSION/g" Packaging/distribution.xml > dist/distribution.xml
PKG="dist/IpBump-$VERSION.pkg"
productbuild --distribution dist/distribution.xml --package-path dist \
    ${IPBUMP_SIGN_INSTALLER:+--sign "$IPBUMP_SIGN_INSTALLER"} "$PKG"

if [ -n "${IPBUMP_NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$PKG" --keychain-profile "$IPBUMP_NOTARY_PROFILE" --wait
    xcrun stapler staple "$PKG"
fi
(cd dist && shasum -a 256 "IpBump-$VERSION.pkg" > "IpBump-$VERSION.pkg.sha256")
echo "Done. The installer is in mac/dist/"
