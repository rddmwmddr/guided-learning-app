#!/bin/sh
# 从提示词库同步提示词。提示词以提示词库为准，本仓库不直接修改。
# 用法：tool/sync_prompts.sh [提示词库路径]
set -e
SRC="${1:-../guided-learning-prompts}/提示词"
DEST="$(dirname "$0")/../assets/prompts"
[ -d "$SRC" ] || { echo "找不到 $SRC"; exit 1; }
cp "$SRC"/*.md "$DEST"/
echo "已同步：$(ls "$DEST" | tr '\n' ' ')"
