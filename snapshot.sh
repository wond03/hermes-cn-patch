#!/bin/sh
# 本机 Hermes 的自维护快照：把「改过的源码 + 构建产物 + 补丁包 + 配置」打包，
# 出问题一条命令还原。默认保留最近 8 份。
#
#   /root/hermes-zh-patch/snapshot.sh            新建一份
#   /root/hermes-zh-patch/snapshot.sh --list     列出已有快照
#   /root/hermes-zh-patch/snapshot.sh --restore <文件|latest>   还原
set -e

REPO="${HERMES_REPO:-/root/.hermes/hermes-agent}"
PATCH=/root/hermes-zh-patch
DEST=/root/backup/hermes-cn
KEEP=8

mkdir -p "$DEST"

if [ "$1" = "--list" ]; then
  ls -lht "$DEST"/snapshot-*.tar.gz 2>/dev/null || echo "还没有快照"
  exit 0
fi

if [ "$1" = "--restore" ]; then
  SRC="$2"
  [ -z "$SRC" ] && { echo "用法：snapshot.sh --restore <文件|latest>"; exit 1; }
  if [ "$SRC" = "latest" ]; then
    SRC=$(ls -t "$DEST"/snapshot-*.tar.gz 2>/dev/null | head -1)
  fi
  [ -f "$SRC" ] || { echo "找不到快照：$SRC"; exit 1; }
  echo "== 还原 $SRC =="
  TMP=$(mktemp -d)
  tar xzf "$SRC" -C "$TMP"
  # 源码
  [ -d "$TMP/repo" ] && (cd "$TMP/repo" && tar cf - .) | (cd "$REPO" && tar xf -)
  # 补丁包
  [ -d "$TMP/patch" ] && rm -rf "$PATCH".restore && cp -a "$TMP/patch" "$PATCH".restore
  if [ -d "$PATCH".restore ]; then
    rm -rf "$PATCH"
    mv "$PATCH".restore "$PATCH"
    chmod +x "$PATCH"/*.sh "$PATCH"/*.py 2>/dev/null || true
  fi
  # 配置
  [ -f "$TMP/config.yaml" ] && cp "$TMP/config.yaml" /root/.hermes/config.yaml
  [ -f "$TMP/SOUL.md" ] && cp "$TMP/SOUL.md" /root/.hermes/SOUL.md
  rm -rf "$TMP"
  systemctl restart hermes-dashboard || true
  sleep 12
  systemctl is-active hermes-dashboard
  echo "还原完成（前端产物随快照一起恢复，无需重新构建）"
  exit 0
fi

TS=$(date +%Y%m%d-%H%M%S)
OUT="$DEST/snapshot-$TS.tar.gz"
WORK=$(mktemp -d)
mkdir -p "$WORK/repo" "$WORK/patch"

echo "== 收集源码改动 =="
cd "$REPO"
git diff > "$WORK/source.diff"
git status --porcelain | awk '$1=="??"{print $2}' | while read -r f; do
  [ -f "$f" ] || continue
  mkdir -p "$WORK/repo/$(dirname "$f")"
  cp "$f" "$WORK/repo/$f"
done
# 已跟踪文件的当前内容（直接存，比 diff 更抗上游变动）
git diff --name-only | while read -r f; do
  [ -f "$f" ] || continue
  mkdir -p "$WORK/repo/$(dirname "$f")"
  cp "$f" "$WORK/repo/$f"
done
# 构建产物（还原后不用再 build）
mkdir -p "$WORK/repo/hermes_cli"
cp -a hermes_cli/web_dist "$WORK/repo/hermes_cli/"

echo "== 收集补丁包与配置 =="
cp -a "$PATCH"/. "$WORK/patch/"
rm -rf "$WORK/patch/backups"
cp /root/.hermes/config.yaml "$WORK/config.yaml"
cp /root/.hermes/SOUL.md "$WORK/SOUL.md" 2>/dev/null || true
git rev-parse HEAD > "$WORK/base_commit.txt"
export PATH="$HOME/.local/bin:$PATH"
hermes --version > "$WORK/version.txt" 2>&1 || true

tar czf "$OUT" -C "$WORK" .
rm -rf "$WORK"

echo "快照：$OUT（$(du -h "$OUT" | cut -f1)）"

# 只保留最近 KEEP 份
ls -t "$DEST"/snapshot-*.tar.gz | tail -n +$((KEEP + 1)) | xargs -r rm -f
