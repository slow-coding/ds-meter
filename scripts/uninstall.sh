#!/bin/bash
# 把这个 app 在系统里留下的东西全清掉（应用、自启、偏好、残留文件、钥匙串里的两串凭据）。
set -euo pipefail

LABEL="app.dsmeter.macos"
APP="/Applications/DS Meter.app"

echo "1) 退出并注销自启（连改名前那版一起）"
for L in "$LABEL" app.deepseekmeter.macos; do
    launchctl bootout "gui/$(id -u)/$L" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$L.plist"
done
pkill -x DSMeter 2>/dev/null || true
echo "   已删 ~/Library/LaunchAgents/*.plist"

echo "2) 删应用"
rm -rf "$APP" "/Applications/DeepSeek Meter.app"
echo "   已删 $APP"

echo "3) 删偏好与本地数据"
defaults delete "$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/Preferences/$LABEL.plist"
rm -rf "$HOME/Library/Application Support/DSMeter" "$HOME/Library/Application Support/DeepSeekMeter"
rm -rf "$HOME/Library/WebKit/$LABEL" "$HOME/Library/WebKit/app.deepseekmeter.macos"
rm -rf "$HOME/Library/Caches/$LABEL" "$HOME/Library/Caches/app.deepseekmeter.macos"
echo "   已删 Preferences / Application Support / WebKit / Caches"

echo "4) 旧版本留在钥匙串里的凭据"
if [ "${1:-}" = "--keychain" ]; then
    # security 读钥匙串会弹一次密码框，所以默认不删；凭据文件已经随上面那步删掉了
    for L in "$LABEL" app.deepseekmeter.macos; do
        security delete-generic-password -s "$L" -a apiKey >/dev/null 2>&1 || true
        security delete-generic-password -s "$L" -a consoleToken >/dev/null 2>&1 || true
    done
    echo "   已删 apiKey / consoleToken"
else
    echo "   跳过（新版凭据在 Application Support/DSMeter，已删；要清旧钥匙串条目跑 ./uninstall.sh --keychain）"
fi

echo "5) 构建缓存（可选，删了下次编译慢 30 秒）"
rm -rf "$HOME/Library/Caches/ds-meter"
echo "   已删 ~/Library/Caches/ds-meter"

echo
echo "源码还在 ~/code/ds-meter（要删自己 rm -rf）"
