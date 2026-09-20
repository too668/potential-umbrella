#!/usr/bin/env bash
# ============================================================
#  tinyproxy 一键安装/重启脚本
#
#  功能:
#    1. 安装 tinyproxy
#    2. 写入宽松配置（无鉴权 / 放开 CONNECT / 允许 0.0.0.0）
#    3. 停止旧进程
#    4. 以 root 身份后台启动（等效于:
#       sudo nohup /usr/bin/tinyproxy -c /etc/tinyproxy/tinyproxy.conf </dev/null >/tmp/tinyproxy.log 2>&1 &
#    5. 校验监听与代理连通性
#
#  用法:
#    bash install-tinyproxy.sh
#
#  可覆盖参数:
#    TINYPROXY_PORT=9000 bash install-tinyproxy.sh
# ============================================================
set -euo pipefail

PORT="${TINYPROXY_PORT:-18889}"
CONF="/etc/tinyproxy/tinyproxy.conf"
LOG="/tmp/tinyproxy.log"

info()  { printf '[INFO] %s\n' "$*"; }
ok()    { printf '[ OK ] %s\n' "$*"; }
warn()  { printf '[WARN] %s\n' "$*"; }

# 1. 获取 root 能力
if [[ $EUID -eq 0 ]]; then
  SUDO=""
else
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    info "使用 sudo 获取 root 权限（可能会要求输入密码）..."
    $SUDO -v
  else
    warn "当前用户不是 root，且系统没有 sudo，尝试继续以当前用户运行"
  fi
fi

info "目标监听端口: $PORT"

# 2. 安装 tinyproxy
info "检查并安装 tinyproxy..."
if ! dpkg -s tinyproxy >/dev/null 2>&1; then
  if [[ $SUDO == "sudo" || $EUID -eq 0 ]]; then
    if [[ $EUID -eq 0 ]]; then
      apt-get update
      apt-get install -y tinyproxy
    else
      $SUDO apt-get update
      $SUDO apt-get install -y tinyproxy
    fi
  else
    warn "无法安装 tinyproxy（缺少 root 权限）"
  fi
else
  ok "tinyproxy 已安装"
fi

# 3. 写入“最大权限”配置
info "写入最大权限配置: $CONF"
if [[ $EUID -eq 0 ]]; then
  tee "$CONF" >/dev/null <<EOF
Port ${PORT}
Bind 0.0.0.0
Timeout 3600
MaxClients 1000
MinUsers 0
StartServers 0
StopServers 0
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
elif [[ $SUDO == "sudo" ]]; then
  $SUDO tee "$CONF" >/dev/null <<EOF
Port ${PORT}
Bind 0.0.0.0
Timeout 3600
MaxClients 1000
MinUsers 0
StartServers 0
StopServers 0
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
else
  warn "无法写入配置（缺少 root 权限），跳过"
fi

# 4. 停掉旧进程
info "停止可能存在的旧 tinyproxy 进程..."
if [[ $EUID -eq 0 ]]; then
  pkill -f "tinyproxy -c ${CONF}" 2>/dev/null || true
  sleep 1
elif [[ $SUDO == "sudo" ]]; then
  $SUDO pkill -f "tinyproxy -c ${CONF}" 2>/dev/null || true
  sleep 1
else
  warn "无法停止旧 tinyproxy（缺少 root 权限）"
fi

# 5. 后台启动（以 root 身份，等效于你给的命令）
info "以 root 身份后台启动 tinyproxy..."
if [[ $EUID -eq 0 ]]; then
  rm -f "$LOG" || true
  nohup /usr/bin/tinyproxy -c "$CONF" </dev/null >"$LOG" 2>&1 &
  ok "tinyproxy 已后台启动 (PID $!)"
elif [[ $SUDO == "sudo" ]]; then
  $SUDO rm -f "$LOG" || true
  $SUDO nohup /usr/bin/tinyproxy -c "$CONF" </dev/null >"$LOG" 2>&1 &
  ok "tinyproxy 已后台启动 (PID $!)"
else
  warn "无法以 root 启动 tinyproxy（缺少 root 权限）"
fi

# 6. 校验监听
info "等待端口监听建立..."
LISTEN_OK=0
for i in $(seq 1 10); do
  sleep 1
  if ss -lnt 2>/dev/null | grep -Eq ":${PORT}( |/|$)" && \
     ss -lnt 2>/dev/null | grep -E ":${PORT}( |/|$)" | grep -Eq "LISTEN"; then
    ok "检测到端口 $PORT 已监听"
    LISTEN_OK=1
    break
  fi
done
if [[ $LISTEN_OK -eq 0 ]]; then
  warn "未检测到端口 $PORT 监听，当前监听情况如下:"
  ss -lnt || true
fi

# 7. 本地访问 + 代理 CONNECT 测试
if curl -Is --max-time 5 "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
  ok "本地访问 http://127.0.0.1:${PORT}/ 成功"
else
  warn "本地访问 http://127.0.0.1:${PORT}/ 暂未成功"
fi

if [[ $LISTEN_OK -eq 1 ]]; then
  info "执行代理 CONNECT 测试..."
  if curl -s --max-time 10 --proxy "http://127.0.0.1:${PORT}" --ssl-no-revoke https://ipinfo.io >/dev/null 2>&1; then
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
 代理测试: curl --proxy http://127.0.0.1:${PORT} --ssl-no-revoke https://ipinfo.io
 日志文件: ${LOG}
==============================

EOF
