#!/usr/bin/env bash
# ============================================================
#  Codespace 内 tinyproxy 一键安装/启动脚本
#  默认监听端口: 8888
#  用法:
#    bash install_tinyproxy.sh
#
#  如果你需要改成别的端口:
#    TINYPROXY_PORT=9000 bash install_tinyproxy.sh
# ============================================================
set -euo pipefail

PORT="${TINYPROXY_PORT:-8888}"

info()  { printf '[INFO] %s\n' "$*"; }
ok()    { printf '[ OK ] %s\n' "$*"; }
warn()  { printf '[WARN] %s\n' "$*"; }

# 1. 获取 root 能力
if [[ $EUID -eq 0 ]]; then
  SUDO=""
else
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    # 一次性获取 root 权限，避免后续反复要密码
    if [[ $SUDO == "sudo" ]]; then
      $SUDO -v
    fi
  else
    echo "需要 root 权限执行此脚本"
    exit 1
  fi
fi

info "目标监听端口: $PORT"

# 2. 安装 tinyproxy
info "检查并安装 tinyproxy..."
if ! dpkg -s tinyproxy >/dev/null 2>&1; then
  $SUDO apt-get update
  $SUDO apt-get install -y tinyproxy
else
  ok "tinyproxy 已安装"
fi

# 3. 写“最大权限”配置（无限制 / 无鉴权 / 放开 CONNECT）
CONF="/etc/tinyproxy/tinyproxy.conf"
info "写入最大权限配置: $CONF"

$SUDO tee "$CONF" >/dev/null <<'EOF'
Port 8888
Bind 0.0.0.0
Timeout 3600
MaxClients 1000
MinUsers 0
MaxClients 1000
StartServers 0
StopServers 0
Timeout 3600
ConnectPort 80
ConnectPort 443
ConnectPort 8080
ConnectPort 3128
ConnectPort 1080
ConnectPort 10808
LogLevel info
UserName root
Allow 0.0.0.0/0
EOF

# 4. 先停掉旧的 tinyproxy 进程，避免端口残留
info "停止可能存在的旧 tinyproxy 进程..."
if $SUDO pkill -f "tinyproxy" 2>/dev/null; then
  ok "已尝试停止旧进程"
  sleep 1
else
  ok "未发现需要停止的旧进程"
fi

# 5. 以 root 身份后台启动 tinyproxy（最大权限，绕开 tinyproxy 用户沙箱）
info "以 root 身份后台启动 tinyproxy..."
LOG="/tmp/tinyproxy.log"
if [[ $SUDO != "" ]]; then
  $SUDO rm -f "$LOG" || true
  $SUDO nohup tinyproxy -c "$CONF" </dev/null >"$LOG" 2>&1 &
  ok "tinyproxy 已后台启动 (PID $!)"
else
  rm -f "$LOG" || true
  nohup tinyproxy -c "$CONF" </dev/null >"$LOG" 2>&1 &
  ok "tinyproxy 已后台启动 (PID $!)"
fi

# 7. 校验
info "等待监听建立..."
LISTEN_OK=0
for i in $(seq 1 10); do
  sleep 1
  if ss -lnt 2>/dev/null | grep -E ":${PORT}(\b|/)" | grep -Eq "LISTEN"; then
    ok "检测到端口 $PORT 已监听"
    LISTEN_OK=1
    break
  fi
done
if [[ $LISTEN_OK -eq 0 ]]; then
  warn "未检测到端口 $PORT 监听"
  warn "当前监听情况如下:"
  ss -lnt || true
fi

if curl -Is --max-time 5 "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
  ok "本地访问 http://127.0.0.1:${PORT}/ 成功"
else
  warn "本地访问 http://127.0.0.1:${PORT}/ 暂未成功"
fi

if [[ $LISTEN_OK -eq 1 ]]; then
  info "执行代理 CONNECT 测试..."
  if curl -xs --max-time 10 "http://127.0.0.1:${PORT}" https://ipinfo.io >/dev/null 2>&1; then
    ok "代理测试 https://ipinfo.io 成功"
  else
    warn "代理测试 https://ipinfo.io 暂未成功，请查看 $LOG"
  fi
fi

cat <<EOF

==============================
 tinyproxy 安装完成
 监听端口: ${PORT}
 本地验证: curl -I http://127.0.0.1:${PORT}/
 代理测试: curl -x http://127.0.0.1:${PORT} https://ipinfo.io
==============================

EOF
