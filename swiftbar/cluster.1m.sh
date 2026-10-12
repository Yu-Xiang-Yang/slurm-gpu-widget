#!/bin/bash
# <swiftbar.title>集群队列</swiftbar.title>
# <swiftbar.desc>Tunnelblick VPN 状态 + Slurm 分区 CPU/GPU 占用</swiftbar.desc>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# 文件名里的 1m 表示每分钟刷新一次
exec "$HOME/.config/cluster-widget/cluster-status.sh" --swiftbar
