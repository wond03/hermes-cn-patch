#!/usr/bin/env bash
# 卸载中文补丁：撤回源码改动，可选停掉控制台服务。
#   ./uninstall.sh            只撤补丁（服务继续跑，但界面回到英文）
#   ./uninstall.sh --service  顺带停掉并删除 hermes-dashboard 服务（保留 ~/.hermes 数据）
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ "${1:-}" = "--service" ] && {
  systemctl disable --now hermes-dashboard 2>/dev/null || true
  rm -f /etc/systemd/system/hermes-dashboard.service
  systemctl daemon-reload
  echo "已停止并移除 hermes-dashboard 服务（~/.hermes 里的会话和配置都还在）"
}
"$HERE/reset.sh"
echo "补丁已撤回。前端产物仍是中文，重新构建或重启后回到英文。"
