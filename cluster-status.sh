#!/bin/bash
# cluster-status.sh — 检测 Tunnelblick VPN，并通过 ssh 查询 Slurm 集群各分区(队列)的 CPU/GPU 占用。
#
# 用法:
#   cluster-status.sh            输出 JSON（给 Übersicht 桌面组件用）
#   cluster-status.sh --swiftbar 输出 SwiftBar 菜单栏格式
#   cluster-status.sh --connect  只让 Tunnelblick 连接 VPN
#
# 配置文件: ~/.config/cluster-widget/config（见 config.example）

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

CONF="${CLUSTER_WIDGET_CONF:-$HOME/.config/cluster-widget/config}"
# 命令行上的环境变量优先于配置文件
_ENV_OVERRIDES="$(env | grep -E '^(TB_CONFIG|SSH_HOST|AUTO_CONNECT|CONNECT_TIMEOUT|SSH_TIMEOUT|PARTITIONS|GPU_ONLY|CLUSTER_NAME|SHOW_NODES|UI_LANG)=' | sed "s/'/'\\\\''/g; s/=\(.*\)/='\1'/")"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"
eval "$_ENV_OVERRIDES"

TB_CONFIG="${TB_CONFIG:-}"              # Tunnelblick 里的配置名；留空则不检测 VPN，直接 ssh
SSH_HOST="${SSH_HOST:-}"                # ssh 目标，建议写 ~/.ssh/config 里的 Host 别名
CLUSTER_NAME="${CLUSTER_NAME:-}"        # 组件标题里显示的集群名；留空显示 "GPU 队列"
SHOW_NODES="${SHOW_NODES:-0}"           # 1=在每个分区下列出节点名及其 GPU/CPU 占用
UI_LANG="${UI_LANG:-auto}"              # 界面语言：zh / en / auto（跟随系统语言）
if [ "$UI_LANG" = "auto" ]; then
  case "$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p')" in
    *zh*) UI_LANG="zh" ;;
    *)    UI_LANG="en" ;;
  esac
fi
[ "$UI_LANG" = "zh" ] || UI_LANG="en"
AUTO_CONNECT="${AUTO_CONNECT:-1}"       # VPN 未连接时是否自动让 Tunnelblick 连接
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-30}"
SSH_TIMEOUT="${SSH_TIMEOUT:-8}"
PARTITIONS="${PARTITIONS:-}"            # 只显示这些分区，逗号分隔；留空显示全部
GPU_ONLY="${GPU_ONLY:-1}"               # 1=只显示有 GPU 的分区、不显示 CPU
MOCK_DIR="${MOCK_DIR:-}"                # 测试用：从目录读取假数据，不碰 VPN 和 ssh

MODE="json"
case "$1" in
  --swiftbar) MODE="swiftbar" ;;
  --connect)  MODE="connect" ;;
esac

# ---------- Tunnelblick ----------

vpn_state() {
  if [ -n "$MOCK_DIR" ]; then cat "$MOCK_DIR/vpn_state" 2>/dev/null || echo CONNECTED; return; fi
  if [ -z "$TB_CONFIG" ]; then echo "NO_CONFIG"; return; fi
  if ! pgrep -xq Tunnelblick; then echo "NOT_RUNNING"; return; fi
  osascript -e "tell application \"Tunnelblick\" to get state of first configuration where name = \"$TB_CONFIG\"" 2>/dev/null \
    || echo "UNKNOWN"
}

vpn_connect() {
  [ -n "$MOCK_DIR" ] && return 0
  [ -z "$TB_CONFIG" ] && return 1
  # 避免多个刷新同时发起连接
  local lock="/tmp/cluster-widget-connect.lock"
  mkdir "$lock" 2>/dev/null || return 0
  if ! pgrep -xq Tunnelblick; then
    open -ga Tunnelblick
    sleep 3
  fi
  osascript -e "tell application \"Tunnelblick\" to connect \"$TB_CONFIG\"" >/dev/null 2>&1
  local waited=0 rc=1
  while [ "$waited" -lt "$CONNECT_TIMEOUT" ]; do
    if [ "$(vpn_state)" = "CONNECTED" ]; then rc=0; break; fi
    sleep 2; waited=$((waited + 2))
  done
  rmdir "$lock" 2>/dev/null
  return $rc
}

if [ "$MODE" = "connect" ]; then
  vpn_connect; exit $?
fi

# ---------- 采集 ----------

STATE="$(vpn_state)"
if [ "$STATE" != "CONNECTED" ] && [ "$AUTO_CONNECT" = "1" ] && [ "$STATE" != "NO_CONFIG" ]; then
  vpn_connect && STATE="CONNECTED"
fi

RAW=""
ERR=""
if [ -z "$SSH_HOST" ] && [ -z "$MOCK_DIR" ]; then
  [ "$UI_LANG" = "zh" ] && ERR="未配置 SSH_HOST" || ERR="SSH_HOST is not configured"
elif [ "$STATE" = "CONNECTED" ] || [ "$STATE" = "NO_CONFIG" ]; then
  # NO_CONFIG：没填 Tunnelblick 配置名时也尝试 ssh（可能本来就在内网）
  if [ -n "$MOCK_DIR" ]; then
    RAW="$(cat "$MOCK_DIR/scontrol"; echo '@@SQUEUE'; cat "$MOCK_DIR/squeue")"
  else
    RAW="$(ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" "$SSH_HOST" \
      "scontrol show node -o 2>/dev/null; echo '@@SQUEUE'; squeue -h -o '%P|%T|%u' 2>/dev/null" 2>&1)"
    rc=$?
    if [ $rc -ne 0 ]; then
      [ "$UI_LANG" = "zh" ] && ERR="ssh 失败: " || ERR="ssh failed: "
      ERR="$ERR$(printf '%s' "$RAW" | tail -1 | tr -d '"\\')"
      RAW=""
    fi
  fi
else
  [ "$UI_LANG" = "zh" ] && ERR="VPN 未连接" || ERR="VPN not connected"
fi

NOW="$(date '+%H:%M:%S')"
export SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ---------- 解析 + 输出 ----------
# 节点行来自 `scontrol show node -o`，每行一个节点，字段形如 Key=Value。
# 按分区汇总：CPU 已用/总数、GPU 已用/总数、节点状态，以及 squeue 的运行/排队作业数。

printf '%s\n' "$RAW" | awk -v mode="$MODE" -v vpn="$STATE" -v err="$ERR" -v now="$NOW" \
  -v filter="$PARTITIONS" -v gpuonly="$GPU_ONLY" -v me="${USER:-}" \
  -v cluster="$CLUSTER_NAME" -v shownodes="$SHOW_NODES" -v lang="$UI_LANG" '
function val(line, key,    i, n, parts) {
  n = split(line, parts, " ")
  for (i = 1; i <= n; i++)
    if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
  return ""
}
# "gpu:a100:8(S:0-1),gpu:v100:2" -> 10 ; 也兼容 "gpu:8"
function gres_gpus(s,    n, i, items, f, k, num, total) {
  total = 0
  if (s == "" || s == "(null)") return 0
  n = split(s, items, ",")
  for (i = 1; i <= n; i++) {
    if (index(items[i], "gpu") != 1) continue
    sub(/\(.*/, "", items[i])
    k = split(items[i], f, ":")
    num = f[k] + 0
    if (k == 1) num = 1
    total += num
  }
  return total
}
# AllocTRES=cpu=32,mem=200G,gres/gpu=4,gres/gpu:a100=4 -> 4
function alloc_gpus(s,    n, i, items) {
  n = split(s, items, ",")
  for (i = 1; i <= n; i++)
    if (index(items[i], "gres/gpu=") == 1) return substr(items[i], 10) + 0
  return 0
}
function want(p) { return filter == "" || index("," filter ",", "," p ",") > 0 }
function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
function bar(used, total,    w, k, s, i) {
  w = 10; s = ""
  k = (total > 0) ? int(used * w / total + 0.5) : 0
  for (i = 0; i < w; i++) s = s (i < k ? "█" : "░")
  return s
}

# 界面文字（SwiftBar 菜单）
function i18n() {
  if (lang == "zh") {
    L["cluster"] = "集群"; L["gpufree"] = "GPU 空闲"; L["run"] = "运行"; L["pend"] = "排队"; L["mine"] = "我的"
    L["free"] = "空闲"; L["maxfree"] = "单节点最多空闲"; L["cards"] = "卡"; L["mig"] = "个 MIG 实例"
    L["nodes"] = "节点"; L["idle"] = "空闲"; L["down"] = "不可用"; L["updated"] = "更新于"
    L["connect"] = "连接 VPN"; L["refresh"] = "刷新"
  } else {
    L["cluster"] = "Cluster"; L["gpufree"] = "GPU free"; L["run"] = "running"; L["pend"] = "pending"; L["mine"] = "mine"
    L["free"] = "free"; L["maxfree"] = "Max free on one node:"; L["cards"] = "GPUs"; L["mig"] = "MIG instances"
    L["nodes"] = "nodes"; L["idle"] = "idle"; L["down"] = "down"; L["updated"] = "Updated"
    L["connect"] = "Connect VPN"; L["refresh"] = "Refresh"
  }
}

BEGIN { sect = "node"; np = 0; i18n() }
$0 == "@@SQUEUE" { sect = "q"; next }
sect == "node" && /NodeName=/ {
  parts = val($0, "Partitions"); if (parts == "") next
  st = tolower(val($0, "State"))
  ca = val($0, "CPUAlloc") + 0; ct = val($0, "CPUTot") + 0
  gres = val($0, "Gres"); gt = gres_gpus(gres); ga = alloc_gpus(val($0, "AllocTRES"))
  is_mig = (gres ~ /gpu:[0-9]+g\.[0-9]+gb/)   # MIG 切分，如 gpu:2g.20gb:12
  bad = (st ~ /down|drain|fail|maint|not_responding|reboot/)
  nm = val($0, "NodeName")
  n = split(parts, pl, ",")
  counted = 0
  for (i = 1; i <= n; i++) {
    p = pl[i]; if (!want(p)) continue
    if (!(p in seen)) { seen[p] = 1; order[++np] = p }
    nodes[p]++
    if (is_mig) mig[p] = 1
    # 节点明细（SHOW_NODES=1 时输出）
    nl[p, nodes[p]] = nm; ns[p, nodes[p]] = st
    nga[p, nodes[p]] = ga; ngt[p, nodes[p]] = gt; nca[p, nodes[p]] = ca; nct[p, nodes[p]] = ct
    if (bad) { down[p]++; continue }     # 不可用节点不计入容量
    cpu_t[p] += ct; cpu_a[p] += ca
    gpu_t[p] += gt; gpu_a[p] += ga
    if (!counted) { all_gt += gt; all_ga += ga; counted = 1 }   # 节点属于多个分区时只算一次
    if (ca == 0 && ga == 0) idle[p]++
    if (gt - ga > maxfree[p]) maxfree[p] = gt - ga   # 单节点最多空闲 GPU，判断能不能跑整机任务
  }
  next
}
sect == "q" && NF {
  split($0, f, "|"); split(f[1], qp, ","); p = qp[1]
  if (f[2] == "RUNNING") run[p]++
  else if (f[2] == "PENDING") pend[p]++
  if (f[3] == me) mine[p]++
}
END {
  if (gpuonly == "1") {   # 去掉没有 GPU 的分区
    k = 0
    for (i = 1; i <= np; i++) if (gpu_t[order[i]] > 0) order[++k] = order[i]
    np = k
  }
  if (mode == "json") {
    printf "{\"lang\":\"%s\",\"cluster\":\"%s\",\"show_nodes\":%s,", lang, jesc(cluster), (shownodes == "1" ? "true" : "false")
    printf "\"time\":\"%s\",\"vpn\":\"%s\",\"error\":\"%s\",\"gpu_only\":%s,\"gpu_used\":%d,\"gpu_total\":%d,\"partitions\":[", now, vpn, jesc(err), (gpuonly == "1" ? "true" : "false"), all_ga, all_gt
    for (i = 1; i <= np; i++) {
      p = order[i]
      printf "%s{\"name\":\"%s\",\"nodes\":%d,\"idle_nodes\":%d,\"down_nodes\":%d,\"cpu_used\":%d,\"cpu_total\":%d,\"gpu_used\":%d,\"gpu_total\":%d,\"gpu_max_free_node\":%d,\"running\":%d,\"pending\":%d,\"mine\":%d,\"mig\":%s", \
        (i > 1 ? "," : ""), jesc(p), nodes[p], idle[p], down[p], cpu_a[p], cpu_t[p], gpu_a[p], gpu_t[p], maxfree[p], run[p], pend[p], mine[p], (mig[p] ? "true" : "false")
      if (shownodes == "1") {
        printf ",\"node_list\":["
        for (j = 1; j <= nodes[p]; j++)
          printf "%s{\"name\":\"%s\",\"state\":\"%s\",\"cpu_used\":%d,\"cpu_total\":%d,\"gpu_used\":%d,\"gpu_total\":%d}", \
            (j > 1 ? "," : ""), jesc(nl[p, j]), jesc(ns[p, j]), nca[p, j], nct[p, j], nga[p, j], ngt[p, j]
        printf "]"
      }
      printf "}"
    }
    print "]}"
    exit
  }
  # SwiftBar：第一行显示在菜单栏，"---" 之后是下拉菜单
  free_g = all_gt - all_ga; tot_g = all_gt
  title = (cluster != "") ? cluster " " : ""
  if (err != "") printf "⚠︎ %s | color=#d9534f\n", (cluster != "" ? cluster : L["cluster"])
  else if (tot_g > 0) printf "🟢 %s%s %d/%d\n", title, L["gpufree"], free_g, tot_g
  else printf "🟢 %s\n", (cluster != "" ? cluster : L["cluster"])
  print "---"
  printf "VPN: %s | color=%s\n", vpn, (vpn == "CONNECTED" ? "#3c9d5d" : "#d9534f")
  if (err != "") printf "%s | color=#d9534f\n", err
  for (i = 1; i <= np; i++) {
    p = order[i]
    print "---"
    printf "%s%s  ·  %s %d  %s %d%s | font=Menlo-Bold\n", p, (mig[p] ? " (MIG)" : ""), L["run"], run[p], L["pend"], pend[p], (mine[p] ? "  (" L["mine"] " " mine[p] ")" : "")
    if (gpu_t[p] > 0) {
      printf "GPU %s %d/%d %s %d | font=Menlo size=12\n", bar(gpu_a[p], gpu_t[p]), gpu_a[p], gpu_t[p], L["free"], gpu_t[p] - gpu_a[p]
      printf "%s %d %s | font=Menlo size=12\n", L["maxfree"], maxfree[p], (mig[p] ? L["mig"] : L["cards"])
    }
    if (gpuonly != "1")
      printf "CPU %s %d/%d %s %d | font=Menlo size=12\n", bar(cpu_a[p], cpu_t[p]), cpu_a[p], cpu_t[p], L["free"], cpu_t[p] - cpu_a[p]
    printf "%s %d  %s %d  %s %d | font=Menlo size=12 color=gray\n", L["nodes"], nodes[p], L["idle"], idle[p], L["down"], down[p]
    if (shownodes == "1")   # 子菜单：每个节点一行
      for (j = 1; j <= nodes[p]; j++) {
        if (ngt[p, j] > 0) printf "--%s  GPU %d/%d  CPU %d/%d  %s | font=Menlo size=12\n", nl[p, j], nga[p, j], ngt[p, j], nca[p, j], nct[p, j], ns[p, j]
        else printf "--%s  CPU %d/%d  %s | font=Menlo size=12\n", nl[p, j], nca[p, j], nct[p, j], ns[p, j]
      }
  }
  print "---"
  printf "%s %s | color=gray\n", L["updated"], now
  print L["connect"] " | bash=\"" ENVIRON["SCRIPT_PATH"] "\" param1=--connect terminal=false refresh=true"
  print L["refresh"] " | refresh=true"
}'
