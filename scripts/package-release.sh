#!/bin/bash
# 打一个「没有开发者签名」的 dmg：universal（arm64 + x86_64），ad-hoc 签名，装出来的包不挂任何人的名字。
# 输出：dist/DS-Meter-<版本>.dmg、dist/SHA256SUMS。不装进 /Applications，不碰凭据。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DS Meter"
VERSION="$(tr -d '[:space:]' < VERSION)"
CACHE="$HOME/Library/Caches/ds-meter/release"
STAGE="$TMPDIR/ds-meter-release"
DIST="dist"

swift build -c release --arch arm64 --arch x86_64 --scratch-path "$CACHE"
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --scratch-path "$CACHE" --show-bin-path)
BIN="$BIN_DIR/DSMeter"
[ -x "$BIN" ] || { echo "没找到产物: $BIN"; exit 1; }

rm -rf "$STAGE" "$DIST"
mkdir -p "$STAGE/$APP_NAME.app/Contents/MacOS" "$STAGE/$APP_NAME.app/Contents/Resources" "$DIST"
cp "$BIN" "$STAGE/$APP_NAME.app/Contents/MacOS/DSMeter"
[ -f assets/AppIcon.icns ] && cp assets/AppIcon.icns "$STAGE/$APP_NAME.app/Contents/Resources/AppIcon.icns"

# 把说明一起放进包里：谁拿到 dmg 都能看到读什么、发给谁
cp LICENSE PRIVACY.md "$STAGE/$APP_NAME.app/Contents/Resources/"

cat > "$STAGE/$APP_NAME.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>DSMeter</string>
    <key>CFBundleIdentifier</key><string>app.dsmeter.macos</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 关键：ad-hoc（`-` 表示不指定身份）。签出来 TeamIdentifier 是空的，不在任何人名下。
codesign --force --sign - --identifier app.dsmeter.macos "$STAGE/$APP_NAME.app" >/dev/null

cp -R "$STAGE/$APP_NAME.app" "$DIST/" 2>/dev/null || true
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DIST/DS-Meter-$VERSION.dmg" >/dev/null

( cd "$DIST" && shasum -a 256 "DS-Meter-$VERSION.dmg" > SHA256SUMS )

# Homebrew cask：只有给了 REPO（CI 里是 owner/repo）才生成，本地跑就打一份占位的
REPO="${REPO:-}"
if [ -n "$REPO" ]; then
    SHA="$(cut -d' ' -f1 "$DIST/SHA256SUMS")"
    cat > "$DIST/ds-meter.rb" <<RUBY
cask "ds-meter" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/DS-Meter-#{version}.dmg"
  name "DS Meter"
  desc "Menu bar meter for DeepSeek API spend"
  homepage "https://github.com/$REPO"

  app "DS Meter.app"
end
RUBY
    echo "cask：dist/ds-meter.rb（${REPO}）"
fi

echo "包好了：dist/DS-Meter-$VERSION.dmg"
echo "校验：dist/SHA256SUMS"
codesign -dv "$STAGE/$APP_NAME.app" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier"
