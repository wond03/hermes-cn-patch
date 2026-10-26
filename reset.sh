#!/usr/bin/env bash
# 把补丁从源码里撤掉，恢复成上游原样（构建产物不动，需要的话自己再 build）。
#
#   ./reset.sh            反向应用所有补丁
#   ./reset.sh --restore  改用最近一次 apply.sh 的备份覆盖回去
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${HERMES_REPO:-$HOME/.hermes/hermes-agent}
[ -d "$REPO/.git" ] || { echo "找不到 Hermes 源码仓库：$REPO"; exit 1; }
cd "$REPO"

if [ "${1:-}" = "--restore" ]; then
  LAST=$(ls -dt "$HERE"/backups/*/ 2>/dev/null | head -1)
  [ -n "$LAST" ] || { echo "没有可用备份"; exit 1; }
  echo "从备份还原：$LAST"
  ( cd "$LAST" && tar cf - . ) | tar xf -
  rm -f "$REPO/web/src/i18n/configDescZh.ts"
  echo "完成"
  exit 0
fi

for p in $(ls -r "$HERE"/patches/*.patch); do
  name=$(basename "$p")
  if git apply --reverse --check "$p" >/dev/null 2>&1; then
    git apply --reverse "$p"
    echo "✓ 已撤回：$name"
  else
    echo "· 本来就没打上：$name"
  fi
done

rm -f "$REPO/web/src/i18n/configDescZh.ts"
echo "源码已恢复上游状态（构建产物仍在，重启后生效的是旧包）"
