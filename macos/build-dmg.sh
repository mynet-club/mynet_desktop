#!/bin/sh
# build-dmg.sh — 把 .pkg 装进 DMG（E-7）
#
# 用法：
#   sh scripts/build-dmg.sh <pkg 文件> [卷名]
#   例：sh macos/build-dmg.sh dist/mynet_agent_darwin_arm64_v1.0.0.pkg
#
# 产物：与 pkg 同名的 .dmg，内含：
#   MyNet Agent.pkg   —— 双击安装
#   README.txt        —— 安装/卸载说明
#
# 为什么 DMG 里是 pkg 而不是 .app：
#   mynetd 是系统级常驻（LaunchDaemon），要写 /opt/mynet 与
#   /Library/LaunchDaemons，必须走 pkg 的管理员授权；拖进
#   Applications 的 .app 装不了这些路径。
set -eu

if [ $# -lt 1 ]; then
  echo "用法: sh build-dmg.sh <pkg 文件> [卷名]" >&2
  exit 2
fi

PKG=$1
VOLNAME=${2:-MyNet Agent}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if [ ! -f "$PKG" ]; then
  echo "✗ pkg 不存在: $PKG" >&2
  exit 1
fi

# 来源记录（DC-3）：优先 pkg 旁 sidecar，其次 agent dist 同源 SOURCES.txt。
SOURCES_TXT="${PKG}.SOURCES.txt"
if [ ! -s "$SOURCES_TXT" ]; then
  echo "✗ 缺 $SOURCES_TXT —— 先跑 build-pkg.sh（会写来源 sidecar）" >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin) ;;
  *)
    echo "✗ DMG 只能在 macOS 上打（hdiutil）。当前: $(uname -s)" >&2
    echo "  请在 Mac 上执行：sh macos/build-dmg.sh $PKG" >&2
    exit 1
    ;;
esac

OUT="${PKG%.pkg}.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT INT TERM

cp "$PKG" "$STAGE/MyNet Agent.pkg"
# 来源记录进 dmg，挂载后可直接核对（DC-3）
cp "$SOURCES_TXT" "$STAGE/SOURCES.txt"

cat > "$STAGE/README.txt" <<'EOF'
MyNet Agent — macOS 安装

1. 双击「MyNet Agent.pkg」，按向导完成安装（需要管理员密码）。
2. 装完后 LaunchDaemon 已自动拉起：
     sudo launchctl print system/club.mynet.mynetd
     tail -f /var/log/mynet/mynetd.log

安装布局：
  /opt/mynet/bin/{mynet,mynetd,mynet_gateway}
  /Library/LaunchDaemons/club.mynet.mynetd.plist
  /opt/mynet/              节点状态与配置（卸载默认保留）

卸载：
  sudo launchctl bootout system/club.mynet.mynetd
  sudo rm -f /Library/LaunchDaemons/club.mynet.mynetd.plist
  sudo rm -rf /opt/mynet
  # 节点身份/密钥在 /opt/mynet/conf，确认不要了再删

下一步（节点身份）：
  sudo /opt/mynet/bin/mynet setup --vpn-type gnb --back-pub <hex>
EOF

# UDZO：zlib 压缩，Finder/装机 U 盘都认
rm -f "$OUT"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$OUT"

# 来源 sidecar：无 hdiutil 环境下也能复核
cp "$SOURCES_TXT" "${OUT}.SOURCES.txt"

echo "✓ $OUT"
echo "✓ ${OUT}.SOURCES.txt（来源 sidecar）"
ls -la "$OUT" "${OUT}.SOURCES.txt"
