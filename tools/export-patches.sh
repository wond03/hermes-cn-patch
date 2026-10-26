#!/usr/bin/env bash
# 从一台「打好补丁」的机器上重新导出 patch（上游发新版、或你自己改了源码后用）。
#
#   ./tools/export-patches.sh ~/.hermes/hermes-agent
#
# 按主题分组写入 patches/，不会碰到 payload/ 里的原创文件。
set -euo pipefail
REPO=${1:-$HOME/.hermes/hermes-agent}
OUT=$(cd "$(dirname "$0")/.." && pwd)/patches
cd "$REPO"

git diff -- web/src/i18n/zh.ts web/src/i18n/en.ts web/src/i18n/types.ts \
            web/src/i18n/context.tsx web/src/App.tsx > "$OUT/01-i18n-core.patch"
git diff -- web/src/components/AutoField.tsx web/src/pages/ConfigPage.tsx \
  > "$OUT/02-config-descriptions.patch"
git diff -- hermes_cli/dashboard_auth/login_page.py > "$OUT/03-login-page.patch"
git diff -- web/src/pages/ChatPage.tsx web/src/pages/FilesPage.tsx web/src/index.css \
            web/src/lib/terminal-appearance.ts web/src/lib/terminal-touch-scroll.ts \
            web/src/components/SharedMetricsConsentBanner.tsx > "$OUT/04-chat-mobile-ux.patch"
git diff -- hermes_cli/web_routers/sessions.py hermes_cli/web_server_sessions.py \
            gateway/platforms/api_server.py > "$OUT/05-session-delete.patch"
git diff -- hermes_cli/web_routers/actions.py > "$OUT/06-update-lock.patch"

wc -l "$OUT"/*.patch
