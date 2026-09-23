#!/bin/sh
# E-7/R3-5：Linux 安装布局
# PREFIX 默认 /opt/mynet；可 PREFIX=/tmp/x sh install-linux.sh（无需 root）
set -e
PREFIX="${PREFIX:-/opt/mynet}"
STATE="${STATE:-/var/lib/mynet}"
SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
install -d "$PREFIX/bin" "$PREFIX/conf" "$STATE" 2>/dev/null || install -d "$PREFIX/bin" "$PREFIX/conf"
for b in mynet mynetd; do
  src=""
  for c in "$SCRIPT_DIR/dist/mynet_agent_"*/$b; do
    [ -f "$c" ] && src=$c && break
  done
  [ -n "$src" ] && install -m 0755 "$src" "$PREFIX/bin/" && echo "installed $PREFIX/bin/$b"
done
if [ -w /etc/systemd/system ] && [ -f "$SCRIPT_DIR/systemd/mynetd.service" ]; then
  install -m 0644 "$SCRIPT_DIR/systemd/mynetd.service" /etc/systemd/system/
  echo "installed systemd unit"
else
  echo "unit file: $SCRIPT_DIR/systemd/mynetd.service (not copied; need root / systemd)"
fi
echo "done: prefix=$PREFIX state=$STATE"
