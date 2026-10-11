#!/bin/zsh
# Builds Notchy for release and packs it into dist/Notchy-<version>.dmg, ready to attach to a
# GitHub release. The app is signed ad hoc (no Apple Developer ID), so people open it once with
# System Settings › Privacy & Security › Open Anyway.
#
#   scripts/release.sh
set -euo pipefail

cd "${0:A:h}/.."
version=$(grep CFBundleShortVersionString project.yml | sed -E 's/.*"(.*)".*/\1/')
# Outside the project, like the Debug build: synced folders add attributes that codesign rejects.
derived=~/Library/Developer/Notchy/ReleaseBuild
app="$derived/Build/Products/Release/Notchy.app"
dmg="dist/Notchy-$version.dmg"

echo "Building Notchy $version"
xcodegen generate --quiet
rm -rf "$derived"
xcodebuild -project Notchy.xcodeproj -scheme Notchy -configuration Release \
  -derivedDataPath "$derived" -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build -quiet

codesign --verify --deep --strict "$app"
built=$(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString)
[[ "$built" == "$version" ]] || { echo "Built version $built, expected $version" >&2; exit 1; }

# The disk image opens to a designed window: Notchy, an arrow and Applications to drag it onto.
# Finder lays the window out from a writable image, which is then compressed. The first run asks
# to let Terminal (or your editor) control Finder.
volume="Notchy $version"
staging=$(mktemp -d)
rw="$staging.rw.dmg"
trap 'hdiutil detach "/Volumes/$volume" -quiet 2>/dev/null || true; rm -rf "$staging" "$rw"' EXIT
ditto "$app" "$staging/Notchy.app"
ln -s /Applications "$staging/Applications"
mkdir "$staging/.background"
swift Design/dmg/background.swift "$staging/.background"
tiffutil -cathidpicheck "$staging/.background/background.png" "$staging/.background/background@2x.png" \
  -out "$staging/.background/background.tiff" 2>/dev/null
rm "$staging/.background/"*.png

hdiutil detach "/Volumes/$volume" -quiet 2>/dev/null || true
hdiutil create -volname "$volume" -srcfolder "$staging" -fs HFS+ -format UDRW -size 60m -quiet "$rw"
hdiutil attach "$rw" -readwrite -noverify -noautoopen -quiet

# Positions match Design/dmg/background.swift; the window's content is 640×420.
osascript <<OSA
tell application "Finder"
    tell disk "$volume"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 840, 568}
        set options to icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 112
        set text size of options to 13
        set background picture of options to file ".background:background.tiff"
        set position of item "Notchy.app" of container window to {170, 220}
        set position of item "Applications" of container window to {470, 220}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA
# The bounds include the title bar; check the content really is 640×420 if the layout looks off.

rm -rf "/Volumes/$volume/.fseventsd"
sync
hdiutil detach "/Volumes/$volume" -quiet
mkdir -p dist
rm -f "$dmg"
hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -quiet -o "$dmg"

echo
echo "Done: $dmg"
shasum -a 256 "$dmg"
echo
echo "Next: tag and upload, for example"
echo "  git tag v$version && git push origin v$version"
echo "  gh release create v$version $dmg --title \"Notchy $version\" --notes-file <notes>"
