#!/usr/bin/env bash
# Hermes Agent 中文补丁 · 一键安装（Linux 云服务器）
#
#   sudo ./install.sh                 已装 Hermes：直接打补丁 + 构建 + 起服务
#   sudo ./install.sh --install-hermes  没装 Hermes：先跑官方安装，再打补丁
#   sudo ./install.sh --no-build      只打源码，不构建
#   ./install.sh --check              只体检，不动系统
#
# 环境变量：
#   PORT=9119            控制台端口
#   HERMES_REPO=...      源码目录（默认 ~/.hermes/hermes-agent）
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
BASE_COMMIT=bf0203a794a07aac3ff764972ab9087baa4e4f4e
REPO=${HERMES_REPO:-$HOME/.hermes/hermes-agent}
PORT=${PORT:-9119}
SERVICE=hermes-dashboard
DO_BUILD=1
CHECK_ONLY=0
INSTALL_HERMES=0

for arg in "$@"; do
  case "$arg" in
    --no-build) DO_BUILD=0 ;;
    --check) CHECK_ONLY=1 ;;
    --install-hermes) INSTALL_HERMES=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "未知参数：$arg"; exit 2 ;;
  esac
done

say() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
warn(){ printf '\033[1;33m  ⚠ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m  ✗ %s\033[0m\n' "$*"; exit 1; }

# ---------------------------------------------------------------- 1. 体检
say "检查环境"
[ "$(uname -s)" = "Linux" ] || die "只支持 Linux（当前 $(uname -s)）"
case "$(uname -m)" in x86_64|aarch64|arm64) ;; *) die "不支持的架构：$(uname -m)" ;; esac
ok "系统：$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -s) / $(uname -m)"
[ "$(id -u)" = "0" ] || warn "当前不是 root，安装 systemd 服务会失败（可用 sudo 重跑）"

FREE_GB=$(df -Pk / | awk 'NR==2{printf "%d", $4/1024/1024}')
MEM_MB=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)
ok "磁盘可用 ${FREE_GB}G，内存 ${MEM_MB}MB"
[ "$FREE_GB" -ge 3 ] || die "磁盘不足 3G，构建前端会失败"
[ "$MEM_MB" -ge 1500 ] || warn "内存小于 1.5G，构建可能被 OOM 杀掉（建议加 swap）"

curl -sS -m 8 -o /dev/null https://registry.npmjs.org/ 2>/dev/null \
  && ok "网络：npm registry 可达" \
  || warn "网络：npm registry 不可达，构建可能失败（国内可配代理后重试）"

if [ "$CHECK_ONLY" = "1" ]; then
  say "体检完成（--check 模式，未做任何修改）"
  exit 0
fi

# ---------------------------------------------------------------- 2. 定位 Hermes
say "定位 Hermes Agent"
if [ -d "$REPO/.git" ]; then
  ok "源码：$REPO"
elif command -v hermes >/dev/null 2>&1; then
  die "找到 hermes 命令但源码不在 $REPO，请用 HERMES_REPO=/path 指定"
elif [ "$INSTALL_HERMES" = "1" ]; then
  say "调用官方安装脚本（下载约 2G，国内可能较慢）"
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive
  [ -d "$REPO/.git" ] || die "官方安装后仍找不到 $REPO"
  ok "Hermes 安装完成"
else
  die "没找到 Hermes。先装：curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
     或加 --install-hermes 让本脚本代劳"
fi

cd "$REPO"
HERMES_BIN=$(command -v hermes || echo "$HOME/.local/bin/hermes")
[ -x "$HERMES_BIN" ] || warn "没找到 hermes 可执行文件（$HERMES_BIN），服务可能起不来"

HEAD=$(git rev-parse HEAD)
if [ "$HEAD" = "$BASE_COMMIT" ]; then
  ok "版本匹配：v0.22.5（$(git rev-parse --short HEAD)）"
else
  warn "补丁基于 v0.22.5（${BASE_COMMIT:0:9}），当前是 $(git rev-parse --short HEAD)"
  warn "结构差异会导致部分补丁失败，脚本会逐个报告"
fi

# ---------------------------------------------------------------- 3. 构建工具
say "检查构建工具"
if ! command -v npm >/dev/null 2>&1; then
  for d in "$HOME"/.hermes/tools/node-*/bin; do
    [ -x "$d/npm" ] && { export PATH="$d:$PATH"; break; }
  done
fi
command -v npm >/dev/null 2>&1 \
  && ok "npm：$(npm -v)（node $(node -v)）" \
  || die "找不到 npm。装一个：apt install -y nodejs npm（或让 Hermes 自带 node 落到 ~/.hermes/tools）"
[ -d "$REPO/web/node_modules" ] || warn "web/node_modules 不存在，构建时需要联网安装依赖"

# ---------------------------------------------------------------- 4. 打补丁
say "应用中文补丁"
BUILD_FLAG=""
[ "$DO_BUILD" = "0" ] && BUILD_FLAG="--no-build"
HERMES_REPO="$REPO" HERMES_SERVICE="$SERVICE" "$HERE/apply.sh" $BUILD_FLAG | sed 's/^/   /'

# ---------------------------------------------------------------- 5. 常驻服务
say "配置控制台服务"
if [ "$DO_BUILD" = "1" ]; then
  if systemctl cat "$SERVICE" >/dev/null 2>&1; then
    ok "服务已存在：$SERVICE（不覆盖你现有的单元，已由 apply.sh 重启）"
  else
    cat > "/etc/systemd/system/${SERVICE}.service" <<UNIT
[Unit]
Description=Hermes Agent Web Dashboard (zh-CN patch)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment=HOME=$HOME
Environment=PATH=$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WorkingDirectory=$HOME
ExecStart=${HERMES_BIN} dashboard --host 0.0.0.0 --port ${PORT} --no-open --skip-build
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now "${SERVICE}.service"
    sleep 10
    ok "已创建并启动：${SERVICE}.service"
  fi
fi

# ---------------------------------------------------------------- 6. 登录密码
say "检查面板登录"
PW=$($HERMES_BIN config get dashboard.basic_auth.password 2>/dev/null | tr -d '\n' || true)
if [ -z "$PW" ] || echo "$PW" | grep -q "not set"; then
  PW=$(openssl rand -base64 24 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-16 || date +%s%N | sha256sum | cut -c1-16)
  $HERMES_BIN config set dashboard.basic_auth.username admin >/dev/null 2>&1 || true
  $HERMES_BIN config set dashboard.basic_auth.password "$PW" >/dev/null
  systemctl restart "$SERVICE" 2>/dev/null || true
  warn "已生成随机密码（请自行改掉）：$PW"
else
  ok "已设置登录密码（不打印，需要时自己 hermes config get dashboard.basic_auth.password）"
  PW="（沿用现有密码）"
fi

# ---------------------------------------------------------------- 7. 总结
IP=$(curl -sS -m 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
say "完成"
cat <<TIP

  控制台：http://${IP}:${PORT}
  用户名：admin
  密码：  ${PW}

  还没放行端口的话：
    云厂商安全组加一条 入站 TCP:${PORT} 允许 0.0.0.0/0
    本机防火墙：ufw allow ${PORT}/tcp   或   firewall-cmd --add-port=${PORT}/tcp --permanent

  常用命令：
    systemctl restart ${SERVICE}     重启控制台
    systemctl status ${SERVICE}      看状态
    ./reset.sh                       撤掉中文补丁（恢复上游原样）
    ./apply.sh                       重新打上

  升级 Hermes 前务必先 ./reset.sh，升级后再 ./apply.sh。
TIP
