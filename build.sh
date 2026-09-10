#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

BD=build
APP="DeepSeek Harness 开关.app"

# ---- version: semantic version from VERSION, build number from BUILD_NO ----
VER=$(head -n1 VERSION)
BUILD_NUM=0
if [ -f BUILD_NO ]; then BUILD_NUM=$(cat BUILD_NO); fi
BUILD_NUM=$((BUILD_NUM + 1))
echo "$BUILD_NUM" > BUILD_NO

rm -rf "$BD" "$APP"
mkdir -p "$BD/AppIcon.iconset" "$BD/modcache"

echo "== [1/4] generate icon =="
swiftc -O -module-cache-path "$BD/modcache" src/draw_icon.swift -o "$BD/draw_icon"
"$BD/draw_icon" "$BD/AppIcon_1024.png"

echo "== [2/4] pack icns =="
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$BD/AppIcon_1024.png" --out "$BD/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" "$BD/AppIcon_1024.png" --out "$BD/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
# iconutil writes temp files only reliably under /tmp in restricted sandboxes
TMPWORK=$(mktemp -d /tmp/dsh-icns.XXXXXX)
cp -R "$BD/AppIcon.iconset" "$TMPWORK/AppIcon.iconset"
iconutil -c icns "$TMPWORK/AppIcon.iconset" -o "$TMPWORK/AppIcon.icns"
cp "$TMPWORK/AppIcon.icns" "$BD/AppIcon.icns"
rm -rf "$TMPWORK"

echo "== [3/4] compile launcher (v$VER build $BUILD_NUM) =="
swiftc -O -module-cache-path "$BD/modcache" \
  src/main.swift src/Icons.swift src/ServiceManager.swift src/TaskMonitor.swift src/Frontmost.swift \
  -o "$BD/DSHLauncher"

echo "== [4/4] assemble .app and sign =="
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BD/DSHLauncher" "$APP/Contents/MacOS/DSHLauncher"
cp "$BD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# 本地化资源（en / zh-Hans / ja / ko）
for lproj in resources/*.lproj; do
  cp -R "$lproj" "$APP/Contents/Resources/"
done

# inject version
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"

echo
echo "done: $(pwd)/$APP  (version v$VER build $BUILD_NUM)"
