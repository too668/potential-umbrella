# Keep-alive heartbeat

该目录用于记录每次保活心跳。`heartbeat.txt` 会被 `scripts/keepalive.sh` 周期性更新并 push，让 Codespace 保持"有活动"状态。

心跳日志 `push.log` 记录 push 过程中的错误输出，方便排查。
