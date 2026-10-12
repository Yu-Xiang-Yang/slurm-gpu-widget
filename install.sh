#!/bin/bash
# 安装：把脚本放到 ~/.config/cluster-widget/，并装上 Übersicht 组件 / SwiftBar 插件（装了哪个就装哪个）
# Install: copy the collector to ~/.config/cluster-widget/ and install the Übersicht widget / SwiftBar plugin
set -e
cd "$(dirname "$0")"

DEST="$HOME/.config/cluster-widget"
mkdir -p "$DEST"
cp cluster-status.sh "$DEST/" && chmod +x "$DEST/cluster-status.sh"
[ -f "$DEST/config" ] || { cp config.example "$DEST/config"; echo "已生成 / created: $DEST/config  (请填写 / edit CLUSTER_NAME, TB_CONFIG, SSH_HOST)"; }

UB="$HOME/Library/Application Support/Übersicht/widgets"
if [ -d "$UB" ]; then
  rm -rf "$UB/cluster-queue.widget"
  cp -R ubersicht/cluster-queue.widget "$UB/"
  echo "已安装 Übersicht 桌面组件 / Übersicht widget installed"
elif [ -d "/Applications/Übersicht.app" ]; then
  echo "Übersicht 已安装但从未启动：请先打开一次 Übersicht，再重新运行 install.sh"
  echo "Übersicht is installed but has never been launched: open it once, then re-run install.sh"
fi

SB="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [ -z "$SB" ] && [ -d "/Applications/SwiftBar.app" ]; then
  # SwiftBar 首次启动会弹窗选择插件目录，这里预先指定一个
  # Pre-set SwiftBar's plugin directory so it does not prompt on first launch
  SB="$HOME/Library/Application Support/SwiftBar/Plugins"
  mkdir -p "$SB"
  defaults write com.ameba.SwiftBar PluginDirectory "$SB"
fi
if [ -n "$SB" ] && [ -d "$SB" ]; then
  cp swiftbar/cluster.1m.sh "$SB/" && chmod +x "$SB/cluster.1m.sh"
  echo "已安装 SwiftBar 菜单栏插件 / SwiftBar plugin installed"
fi

echo "测试 / test: $DEST/cluster-status.sh"
