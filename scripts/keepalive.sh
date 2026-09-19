#!/usr/bin/env bash
# ============================================================
#  GitHub Codespace 保活脚本
#  周期性产生 git 变更并 push，让 codespace 因"有活动"而不被空闲回收
#  用法:
#    bash scripts/keepalive.sh                  # 前台一直跑
#    bash scripts/keepalive.sh 60                # 自定义间隔秒数(默认 180)
#  后台跑:
#    nohup bash scripts/keepalive.sh > /dev/null 2>&1 &
# ============================================================
set -uo pipefail

INTERVAL="${1:-180}"   # 默认每 3 分钟一次
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

touch keepalive/.keepalive

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S') UTC" "$*"
}

log "keepalive started, interval=${INTERVAL}s, pid=$$"
while true; do
  # 生成一个每次必变的变更
  {
    printf '%s\n' "last activity: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    printf 'pid: %s\n' "$$"
  } > keepalive/heartbeat.txt

  # 把心跳文件放进版本控制
  git add keepalive/heartbeat.txt

  if git diff --cached --quiet 2>/dev/null; then
    log "skip: no change"
  else
    git commit -m "keepalive $(date -u '+%Y-%m-%d %H:%M:%S UTC')" -q
    if git push -q origin HEAD 2>> keepalive/push.log; then
      log "push ok"
    else
      log "push FAILED, see keepalive/push.log"
    fi
  fi

  sleep "$INTERVAL"
done
