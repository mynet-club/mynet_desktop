#!/bin/sh
# E-7：Linux 安装布局（bin/conf/var）
set -e
PREFIX="${PREFIX:-/opt/mynet}"
install -d "$PREFIX/bin" "$PREFIX/conf" /var/lib/mynet
install -m 0755 dist/mynet_agent_linux_*/mynetd "$PREFIX/bin/"
install -m 0755 dist/mynet_agent_linux_*/mynet "$PREFIX/bin/"
install -m 0644 systemd/mynetd.service /etc/systemd/system/
systemctl daemon-reload
echo "installed to $PREFIX; enable: systemctl enable --now mynetd"
