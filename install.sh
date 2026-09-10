#!/bin/bash
# DeepSeek Harness 开关 · 一键安装到 /Applications
# 用法：sh -c "$(curl -fsSL https://raw.githubusercontent.com/wjingshan/dsh-dock-launcher/main/install.sh)"
set -euo pipefail

REPO="wjingshan/dsh-dock-launcher"
APP="DeepSeek Harness 开关.app"
DEST="/Applications/$APP"

echo "==> 查询最新版本…"
API="https://api.github.com/repos/$REPO/releases/latest"
ZIP_URL=$(curl -fsSL "$API" | grep '"browser_download_url"' | grep -o 'https://[^"]*macOS-arm64\.zip' | head -1 || true)
if [ -z "${ZIP_URL:-}" ]; then
  echo "✗ 未能取到安装包地址（网络或仓库问题）。可手动前往："
  echo "  https://github.com/$REPO/releases/latest"
  exit 1
fi
echo "    $ZIP_URL"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "==> 下载中…"
curl -fL --progress-bar -o "$TMP/app.zip" "$ZIP_URL"

echo "==> 解压…"
ditto -x -k "$TMP/app.zip" "$TMP/extract"
SRC="$TMP/extract/$APP"
if [ ! -d "$SRC" ]; then
  echo "✗ 解压后未找到 App，安装包结构异常。"
  exit 1
fi

echo "==> 安装到 $DEST"
if [ -w /Applications ]; then
  rm -rf "$DEST"
  ditto "$SRC" "$DEST"
else
  echo "    （需要管理员权限）"
  sudo rm -rf "$DEST"
  sudo ditto "$SRC" "$DEST"
fi

# 去掉“来自网络下载”的隔离标记，避免首次打开被拦
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> 完成 ✅  正在启动…"
open "$DEST"
echo
echo "使用：左键点击 Dock 图标 = 启动/回到 dsh 页面；右键点击 = 操作菜单（停止服务、动画开关等）。"
