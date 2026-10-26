#!/bin/sh
# 重建前端并重新挂载中文覆盖层 / PWA 清单，然后重启控制台并自检。
# 改完 web/src 下的任何文件后跑这一条，不用记那串 npm 命令。
set -e

REPO="${HERMES_REPO:-/root/.hermes/hermes-agent}"
PATCH=/root/hermes-zh-patch

echo "== 1/4 构建前端 =="
cd "$REPO/web"
HERMES_WEB_BUILD_LIGHT=1 npm run build 2>&1 | tail -3

echo "== 2/4 挂载覆盖层 + PWA =="
python3 "$PATCH/inject_overlay.py" "$REPO" >/dev/null
[ -f "$PATCH/inject_pwa.py" ] && python3 "$PATCH/inject_pwa.py" "$REPO" >/dev/null 2>&1 || true

echo "== 3/4 重启控制台 =="
systemctl restart hermes-dashboard
sleep 12

echo "== 4/4 自检 =="
systemctl is-active hermes-dashboard
curl -s -o /dev/null -w "  /login: %{http_code}\n" http://127.0.0.1:9119/login
if grep -qs "zh-overlay.js" "$REPO/hermes_cli/web_dist/index.html"; then
  echo "  覆盖层：已挂载"
else
  echo "  覆盖层：⚠ 未挂载"
fi
echo "完成。手机上下拉刷新即可看到新版本。"
