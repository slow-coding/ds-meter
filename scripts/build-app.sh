#!/bin/bash
# 编出一份 .app 装到 /Applications。构建缓存放 ~/Library/Caches，工程里不留编译产物。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DS Meter"
CACHE="$HOME/Library/Caches/ds-meter/swiftpm"
STAGE="$TMPDIR/ds-meter-stage"

swift build -c release --scratch-path "$CACHE" 2>&1 | tail -3
BIN_DIR=$(swift build -c release --scratch-path "$CACHE" --show-bin-path)
BIN="$BIN_DIR/DSMeter"
[ -x "$BIN" ] || { echo "没找到产物: $BIN"; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE/$APP_NAME.app/Contents/MacOS"
cp "$BIN" "$STAGE/$APP_NAME.app/Contents/MacOS/DSMeter"

# 图标：assets/AppIcon.icns 由 scripts/make-icon.swift 生成，换图标要重跑那支脚本再打包
mkdir -p "$STAGE/$APP_NAME.app/Contents/Resources"
if [ -f assets/AppIcon.icns ]; then
    cp assets/AppIcon.icns "$STAGE/$APP_NAME.app/Contents/Resources/AppIcon.icns"
else
    echo "提示：assets/AppIcon.icns 不存在，先跑 swift scripts/make-icon.swift"
fi

cat > "$STAGE/$APP_NAME.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DS Meter</string>
    <key>CFBundleDisplayName</key><string>DS Meter</string>
    <key>CFBundleExecutable</key><string>DSMeter</string>
    <key>CFBundleIdentifier</key><string>app.dsmeter.macos</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <!-- 界面语言只有中英两份，文案表在 Sources/DSMeter/L10n.swift（不走 .lproj）。
         这两行是给系统看的：有了它，「系统设置 → 语言与地区 → 应用程序」里才能单给本 App 指定语言，
         系统会把选的语言写进本 App 偏好的 AppleLanguages，L10n 读的就是那一条。 -->
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>zh-Hans</string></array>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 签名：设了 SIGN_ID 就用自己的证书（钥匙串认得出同一个 app，重编不用再授权）；
# 没设就 ad-hoc——自己用没问题，换签名等于换了个 app，权限和登录项要重新给。
SIGN_ID="${SIGN_ID:-}"
if [ -n "$SIGN_ID" ] && security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID"; then
    codesign --force --sign "$SIGN_ID" --identifier app.dsmeter.macos "$STAGE/$APP_NAME.app" >/dev/null 2>&1
    echo "签名：$SIGN_ID"
else
    codesign --force --sign - "$STAGE/$APP_NAME.app" >/dev/null 2>&1
    echo "签名：ad-hoc（没设 SIGN_ID，或本机没有那张证书）"
fi

# 改名前那版（DeepSeek Meter）：旧 app 和旧自启一起清掉，否则登录项会指着不存在的路径。
launchctl bootout "gui/$(id -u)/app.deepseekmeter.macos" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/app.deepseekmeter.macos.plist"
rm -rf "/Applications/DeepSeek Meter.app"

pkill -x DSMeter 2>/dev/null || true
pkill -x DeepSeekMeter 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app"
ditto "$STAGE/$APP_NAME.app" "/Applications/$APP_NAME.app"
rm -rf "$STAGE"
echo "装好了: /Applications/$APP_NAME.app"
