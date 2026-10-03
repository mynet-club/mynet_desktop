#!/bin/sh
# build-pkg.sh — 打 macOS 安装包 .pkg（E-7）
#
# 用法：
#   sh scripts/build-pkg.sh <darwin 产物目录> [version]
#   例：sh macos/build-pkg.sh ../mynet_agent/dist/mynet_agent_darwin_arm64_v1.0.0 v1.0.0
#
# 产物：dist/mynet_agent_darwin_<arch>_<version>.pkg
# 布局：
#   /Applications/MyNet.app          ← 启动台图标（托盘 Agent）
#   /opt/mynet/bin/{mynet,mynetd,mynet_gateway,mynet_tray,webui.html}
#   /Library/LaunchDaemons/club.mynet.mynetd.plist
#   /opt/mynet/share/INSTALL.txt
#
# 安装过程（pkg 的 scripts/）：
#   preinstall  — 升级时先 bootout 旧服务，避免「文件占用 / 双实例」
#   postinstall — 建 /var/lib/mynet，bootstrap launchd
set -eu

if [ $# -lt 1 ]; then
  echo "用法: sh build-pkg.sh <darwin 产物目录> [version]" >&2
  exit 2
fi

SRCDIR=$1
VERSION=${2:-v0.0.0-dev}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
AGENT_DIST=$(cd "$SRCDIR" && pwd)

for b in mynet mynetd; do
  if [ ! -f "$AGENT_DIST/$b" ]; then
    echo "✗ 缺 $AGENT_DIST/$b —— 先在 mynet_agent 跑 make dist" >&2
    exit 1
  fi
done

# 从产物目录名反推 arch：mynet_agent_darwin_<arch>_<ver>
base=$(basename "$AGENT_DIST")
arch=$(printf '%s' "$base" | sed -n 's/^mynet_agent_darwin_\([^_]*\)_.*/\1/p')
[ -n "$arch" ] || arch=universal

PKG_ID=club.mynet.agent
OUT_DIR="$ROOT/dist"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT INT TERM

# ── 1. 拼 payload ────────────────────────────────────────────
PAYLOAD="$STAGE/payload"
mkdir -p \
  "$PAYLOAD/opt/mynet/bin" \
  "$PAYLOAD/opt/mynet/share" \
  "$PAYLOAD/Library/LaunchDaemons"

install -m 0755 "$AGENT_DIST/mynet"         "$PAYLOAD/opt/mynet/bin/"
install -m 0755 "$AGENT_DIST/mynetd"        "$PAYLOAD/opt/mynet/bin/"
if [ -f "$AGENT_DIST/mynet_gateway" ]; then
  install -m 0755 "$AGENT_DIST/mynet_gateway" "$PAYLOAD/opt/mynet/bin/"
fi
if [ -f "$AGENT_DIST/mynet_tray" ]; then
  install -m 0755 "$AGENT_DIST/mynet_tray" "$PAYLOAD/opt/mynet/bin/"
fi
if [ -f "$AGENT_DIST/webui.html" ]; then
  install -m 0644 "$AGENT_DIST/webui.html"    "$PAYLOAD/opt/mynet/bin/"
fi

# ── 1b. MyNet.app（启动台/应用程序里的图标入口）──────────────
# 托盘必须是 .app 才能进 Launchpad / 「应用程序」文件夹。
# LSUIElement=true：纯菜单栏 Agent，不在 Dock 占位。
APP="$PAYLOAD/Applications/MyNet.app/Contents"
mkdir -p "$APP/MacOS" "$APP/Resources"
if [ -f "$AGENT_DIST/mynet_tray" ]; then
  install -m 0755 "$AGENT_DIST/mynet_tray" "$APP/MacOS/MyNet"
fi
# 图标：优先用预生成的 AppIcon.icns；否则从 png 现场转
ICNS_SRC="$SCRIPT_DIR/../assets/AppIcon.icns"
if [ -f "$ICNS_SRC" ]; then
  cp "$ICNS_SRC" "$APP/Resources/AppIcon.icns"
elif [ -f "$ICON_SRC" ] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  ISET="$STAGE/MyNet.iconset"
  mkdir -p "$ISET"
  sips -z 16 16   "$ICON_SRC" --out "$ISET/icon_16x16.png" >/dev/null
  sips -z 32 32   "$ICON_SRC" --out "$ISET/diana@example.net" >/dev/null
  sips -z 32 32   "$ICON_SRC" --out "$ISET/icon_32x32.png" >/dev/null
  sips -z 64 64   "$ICON_SRC" --out "$ISET/nancy@example.org" >/dev/null
  sips -z 128 128 "$ICON_SRC" --out "$ISET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SRC" --out "$ISET/ivan@example.com" >/dev/null
  sips -z 256 256 "$ICON_SRC" --out "$ISET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SRC" --out "$ISET/ethan@example.com" >/dev/null
  sips -z 512 512 "$ICON_SRC" --out "$ISET/icon_512x512.png" >/dev/null
  iconutil -c icns "$ISET" -o "$APP/Resources/AppIcon.icns" 2>/dev/null || true
fi
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MyNet</string>
  <key>CFBundleDisplayName</key><string>MyNet</string>
  <key>CFBundleIdentifier</key><string>club.mynet.tray</string>
  <key>CFBundleExecutable</key><string>MyNet</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION#v}</string>
  <key>CFBundleVersion</key><string>${VERSION#v}</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# launchd plist：ProgramArguments 必须是绝对路径（check.sh 会查）
# Label 与文件名一致：club.mynet.mynetd
cat > "$PAYLOAD/Library/LaunchDaemons/club.mynet.mynetd.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>club.mynet.mynetd</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/mynet/bin/mynetd</string>
    <string>-listen</string>
    <string>127.0.0.1:8096</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>MYNET_HOME</key>
    <string>/var/lib/mynet</string>
    <key>MYNET_BIN</key>
    <string>/opt/mynet/bin/mynet</string>
    <key>PATH</key>
    <string>/opt/mynet/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/mynet/mynetd.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/mynet/mynetd.err</string>
</dict>
</plist>
PLIST

cat > "$PAYLOAD/opt/mynet/share/INSTALL.txt" <<EOF
MyNet Agent ${VERSION} (darwin/${arch})

启动台 / 应用程序：
  /Applications/MyNet.app     托盘（菜单栏图标）

命令行 / 服务：
  /opt/mynet/bin/mynet          执行器
  /opt/mynet/bin/mynetd         常驻通信层
  /opt/mynet/bin/mynet_gateway  边缘网关
  /Library/LaunchDaemons/club.mynet.mynetd.plist

服务管理：
  sudo launchctl kickstart -k system/club.mynet.mynetd
  sudo launchctl bootout    system/club.mynet.mynetd
  tail -f /var/log/mynet/mynetd.log

下一步（节点身份）：
  1) sudo /opt/mynet/bin/mynet setup --local --node-id <id>
  2) open http://127.0.0.1:8096/ui/
EOF

# ── 2. scripts/（preinstall / postinstall）────────────────────
SCRIPTS="$STAGE/scripts"
mkdir -p "$SCRIPTS"
cp "$SCRIPT_DIR/scripts/preinstall"  "$SCRIPTS/preinstall"
cp "$SCRIPT_DIR/scripts/postinstall" "$SCRIPTS/postinstall"
chmod 0755 "$SCRIPTS/preinstall" "$SCRIPTS/postinstall"

# ── 3. pkgbuild ──────────────────────────────────────────────
mkdir -p "$OUT_DIR"
PKG="$OUT_DIR/mynet_agent_darwin_${arch}_${VERSION}.pkg"

# --ownership recommended：root:wheel，与系统目录一致
pkgbuild \
  --root "$PAYLOAD" \
  --scripts "$SCRIPTS" \
  --identifier "$PKG_ID" \
  --version "${VERSION#v}" \
  --install-location / \
  --ownership recommended \
  "$PKG"

echo "✓ $PKG"
ls -la "$PKG"
