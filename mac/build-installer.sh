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

# Two packages. The app goes in as a component, which leaves /Applications itself alone. The helper and the
# launchd files go into /Library, whose folders the payload mirrors exactly, so Installer finds nothing to change.
pkgbuild --component "$APP" --install-location /Applications --identifier io.github.discoveruz.ipbump.app \
    --version "$VERSION" dist/component.pkg
# pkgbuild marks a component's bundle relocatable: Installer then updates any other copy with the same id
# (mac/dist/IpBump.app, say) instead of installing /Applications/IpBump.app. Its option against that needs --root,
# which would record /Applications' own permissions, so the mark comes out of the finished package instead
pkgutil --expand dist/component.pkg dist/component
sed -i '' '/<relocate>/,/<\/relocate>/{/<bundle /d;}' dist/component/PackageInfo
pkgutil --flatten dist/component dist/IpBump-app.pkg
rm -rf dist/component dist/component.pkg dist/check
pkgutil --expand dist/IpBump-app.pkg dist/check
[ "$(xmllint --xpath 'count(/pkg-info/relocate/bundle)' dist/check/PackageInfo)" = 0 ] \
    || { echo "IpBump.app came out relocatable"; exit 1; }

LIBRARY=dist/library
mkdir -p "$LIBRARY/PrivilegedHelperTools" "$LIBRARY/LaunchDaemons" "$LIBRARY/LaunchAgents"
cp dist/io.github.discoveruz.ipbump.helper "$LIBRARY/PrivilegedHelperTools/"
cp Packaging/io.github.discoveruz.ipbump.helper.plist "$LIBRARY/LaunchDaemons/"
cp Packaging/io.github.discoveruz.ipbump.plist "$LIBRARY/LaunchAgents/"
chmod 755 "$LIBRARY" "$LIBRARY/LaunchDaemons" "$LIBRARY/LaunchAgents" "$LIBRARY/PrivilegedHelperTools/io.github.discoveruz.ipbump.helper"
chmod 1755 "$LIBRARY/PrivilegedHelperTools"
chmod 644 "$LIBRARY"/LaunchDaemons/*.plist "$LIBRARY"/LaunchAgents/*.plist
pkgbuild --root "$LIBRARY" --install-location /Library --scripts Packaging/scripts --ownership recommended \
    --identifier io.github.discoveruz.ipbump.helper --version "$VERSION" dist/IpBump-helper.pkg

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
