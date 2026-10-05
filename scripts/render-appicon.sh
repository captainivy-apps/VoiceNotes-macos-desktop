#!/usr/bin/env bash
# 从 scripts/appicon/AppIcon.svg 生成 macOS AppIcon.appiconset 的全部尺寸 PNG。
# 依赖 macOS 自带的 qlmanage 与 sips（无需额外安装）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/scripts/appicon/AppIcon.svg"
OUT="$ROOT/VoiceNotes/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "渲染 SVG 母版 (1024px)..."
qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null
MASTER="$TMP/AppIcon.svg.png"
[ -f "$MASTER" ] || { echo "错误: qlmanage 未能渲染 $SVG" >&2; exit 1; }

render() { # name size
  sips -z "$2" "$2" "$MASTER" --out "$OUT/$1" >/dev/null
}

echo "生成各尺寸 PNG..."
cp "$MASTER" "$OUT/icon_512x512@2x.png"   # 1024
render icon_512x512.png      512
render icon_256x256@2x.png   512
render icon_256x256.png      256
render icon_128x128@2x.png   256
render icon_128x128.png      128
render icon_32x32@2x.png      64
render icon_32x32.png         32
render icon_16x16@2x.png      32
render icon_16x16.png         16

echo "完成 -> $OUT"
