#!/usr/bin/env bash
# 把中文补丁打到已安装的 Hermes Agent 上。
#
#   ./apply.sh              打补丁 + 构建前端 + 重启控制台
#   ./apply.sh --no-build   只打源码，不构建（调试用）
#   ./apply.sh --check      只检查能否干净应用，不写入
#
# 环境变量：
#   HERMES_REPO   源码目录，默认 ~/.hermes/hermes-agent
#   HERMES_SERVICE  systemd 单元名，默认 hermes-dashboard（不存在则跳过重启）
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${HERMES_REPO:-$HOME/.hermes/hermes-agent}
SERVICE=${HERMES_SERVICE:-hermes-dashboard}
BASE_COMMIT=bf0203a794a07aac3ff764972ab9087baa4e4f4e
BUILD=1
CHECK_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    --check) CHECK_ONLY=1 ;;
    *) echo "未知参数：$arg"; exit 2 ;;
  esac
done

[ -d "$REPO/.git" ] || { echo "找不到 Hermes 源码仓库：$REPO"; exit 1; }
cd "$REPO"

HEAD=$(git rev-parse HEAD)
# 构建用的 npm 可能在 Hermes 自带的 node 里
if ! command -v npm >/dev/null 2>&1; then
  for d in "$HOME"/.hermes/tools/node-*/bin; do
    [ -x "$d/npm" ] && { export PATH="$d:$PATH"; break; }
  done
fi

echo "目标仓库：$REPO"
echo "当前版本：$(git rev-parse --short HEAD)"
if [ "$HEAD" != "$BASE_COMMIT" ]; then
  echo "⚠ 补丁是按 ${BASE_COMMIT:0:9} 写的，当前是 ${HEAD:0:9}。"
  echo "  上游结构变过的话部分补丁会匹配失败（脚本会逐个报告，不会中断已成功的）。"
fi

# 备份会被改到的文件
BACKUP="$HERE/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
for f in $(grep -h '^+++ b/' "$HERE"/patches/*.patch 2>/dev/null | sed 's|^+++ b/||' | sort -u); do
  [ -f "$f" ] && { mkdir -p "$BACKUP/$(dirname "$f")"; cp "$f" "$BACKUP/$f"; }
done
echo "备份：$BACKUP"

applied=0; skipped=0; failed=0
for p in "$HERE"/patches/*.patch; do
  name=$(basename "$p")
  if git apply --reverse --check "$p" >/dev/null 2>&1; then
    echo "· 已是新状态：$name"
    skipped=$((skipped + 1))
    continue
  fi
  if ! git apply --check "$p" >/dev/null 2>&1; then
    echo "⚠ 无法应用（上游结构变了？）：$name"
    failed=$((failed + 1))
    continue
  fi
  if [ "$CHECK_ONLY" = "1" ]; then
    echo "✓ 可应用：$name"
    continue
  fi
  git apply "$p"
  echo "✓ 已应用：$name"
  applied=$((applied + 1))
done

if [ "$CHECK_ONLY" = "1" ]; then
  exit 0
fi

# 新增文件（补丁之外的原创文件）
cp "$HERE/payload/configDescZh.ts" "$REPO/web/src/i18n/configDescZh.ts"
echo "✓ 配置说明对照表：908 条"

if [ "$BUILD" = "1" ]; then
  echo "== 构建前端（1–2 分钟）=="
  ( cd "$REPO/web" && HERMES_WEB_BUILD_LIGHT=1 npm run build )
  echo "== 挂载中文覆盖层 + PWA 清单 =="
  python3 "$HERE/tools/inject_overlay.py" "$REPO" >/dev/null
  if [ -f "$HERE/tools/inject_pwa.py" ]; then
    python3 "$HERE/tools/inject_pwa.py" "$REPO" >/dev/null 2>&1 || true
  fi
  if grep -q "zh-overlay.js" "$REPO/hermes_cli/web_dist/index.html"; then
    echo "✓ 覆盖层已挂载（词典 $(grep -c '": "' "$HERE/payload/zhOverlay.js") 条）"
  else
    echo "✗ 覆盖层没有挂上（index.html 里找不到 zh-overlay.js），请检查 tools/inject_overlay.py"
    exit 1
  fi
  if systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE}\.service"; then
    systemctl restart "$SERVICE"
    sleep 8
    echo "服务：$(systemctl is-active "$SERVICE")"
  fi
fi

echo
echo "完成：应用 $applied 个，跳过 $skipped 个，失败 $failed 个"
[ "$failed" -gt 0 ] && echo "失败项通常是上游改了结构，需要按新版重做对应补丁。"
exit 0
