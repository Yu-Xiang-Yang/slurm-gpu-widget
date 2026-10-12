#!/bin/bash
# <swiftbar.title>集群队列 / Cluster Queue</swiftbar.title>
# <swiftbar.desc>Tunnelblick VPN 状态 + Slurm 分区 GPU/CPU 占用 + 我的作业</swiftbar.desc>
# <swiftbar.type>streamable</swiftbar.type>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
#
# 流式插件：后台每 REFRESH_SECONDS 秒查询一次集群；前台每秒重绘一次，作业时长本地递增。
# Streamable plugin: the cluster is queried every REFRESH_SECONDS in the background,
# while the menu is re-rendered every second so that job timers tick locally.

SCRIPT="$HOME/.config/cluster-widget/cluster-status.sh"
CACHE_DIR="$HOME/.cache/cluster-widget"
OUT="$CACHE_DIR/swiftbar-stream.txt"
REFRESH_SECONDS="${REFRESH_SECONDS:-15}"
mkdir -p "$CACHE_DIR"

# 后台采集循环；主进程退出（SwiftBar 停止插件）时一并退出
MAIN=$$
(
  while kill -0 "$MAIN" 2>/dev/null; do
    "$SCRIPT" --swiftbar-stream > "$OUT.tmp" 2>/dev/null && [ -s "$OUT.tmp" ] && mv -f "$OUT.tmp" "$OUT"
    sleep "$REFRESH_SECONDS"
  done
) &
FETCH=$!
trap 'kill "$FETCH" 2>/dev/null; exit 0' EXIT INT TERM

# 每秒渲染一次；内容有变化时才输出新的一帧（先输出 ~~~，SwiftBar 以此清空上一帧），避免无作业时菜单栏闪烁
LAST=""
while true; do
  if [ -s "$OUT" ]; then
    # 把 @@EL:已运行秒数:采集时刻:时限秒数@@ 替换为当前的已运行时长
    FRAME="$(awk -v now="$(date +%s)" '
      function p2(n) { return sprintf("%02d", n) }
      function fmt(s,    d, h, m) {
        d = int(s / 86400); h = int((s % 86400) / 3600); m = int((s % 3600) / 60)
        return (d > 0 ? d "-" p2(h) : h) ":" p2(m) ":" p2(s % 60)
      }
      {
        while (match($0, /@@EL:[0-9]+:[0-9]+:-?[0-9]+@@/)) {
          split(substr($0, RSTART + 5, RLENGTH - 7), a, ":")
          s = a[1] + now - a[2]; if (s < a[1]) s = a[1]
          if (a[3] >= 0 && s > a[3]) s = a[3]
          $0 = substr($0, 1, RSTART - 1) fmt(s) substr($0, RSTART + RLENGTH)
        }
        print
      }' "$OUT")"
  else
    FRAME="… | color=gray"
  fi
  if [ "$FRAME" != "$LAST" ]; then
    echo "~~~"
    printf '%s\n' "$FRAME"
    LAST="$FRAME"
  fi
  sleep 1
done
