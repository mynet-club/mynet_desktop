#!/bin/sh
# E-7/R3-5：Linux 安装布局
# PREFIX 默认 /opt/mynet；可 PREFIX=/tmp/x sh install-linux.sh（无需 root）
#
# ⚠️ 缺产物必须**失败**，不能静默装个空布局还报 done —— 与 mynet_openwrt 的
# V2-9 同源教训（`[ -f … ] && … || true` 让缺文件时静默产出空 ipk）。
set -e
PREFIX="${PREFIX:-/opt/mynet}"
STATE="${STATE:-/opt/mynet}"
SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)

if ! install -d "${PREFIX}/bin" "${PREFIX}/conf"; then
  echo "✗ 无法创建 ${PREFIX}/bin 与 ${PREFIX}/conf（检查 PREFIX 是否可写）" >&2
  exit 1
fi

# STATE 通常是 /opt/mynet，非 root 装时创建不了 —— 这不是错误，
# 但**不能假装创建成功了**（旧版无论成不成都打印 state=$STATE）。
if install -d "${STATE}" 2>/dev/null; then
  STATE_NOTE="${STATE}（已创建）"
else
  STATE_NOTE="${STATE}（未创建：需 root，运行期由 mynetd 自建）"
fi

for b in mynet mynetd; do
  src=""
  for c in "$SCRIPT_DIR/dist/mynet_agent_"*/"$b"; do
    if [ -f "$c" ]; then src=$c; break; fi
  done
  if [ -z "$src" ]; then
    echo "✗ 找不到 ${b}：${SCRIPT_DIR}/dist/mynet_agent_*/${b} 不存在" >&2
    echo "  先在 mynet_agent 跑 \`make dist\`，或把产物放到该路径下" >&2
    exit 1
  fi
  install -m 0755 "$src" "${PREFIX}/bin/"
  echo "installed ${PREFIX}/bin/${b}"
done

# 服务装配**委托 `mynet install`**：它写内嵌 unit + /etc/mynet/mynetd.env 并 enable/start。
# 安装器只落文件 —— 合同「系统登记只有一个 owner」（旧版本脚本自己拷 unit，已撤）。
if [ -w /etc/systemd/system ] && [ "$PREFIX" = "/opt/mynet" ]; then
  GW="${MYNET_GATEWAYS:-wss://gw.mynet.club/v1/node/connect}"
  echo "▸ 委托 mynet install 装配服务（gateways=${GW}）"
  MYNET_HOME="$STATE" "${PREFIX}/bin/mynet" install --gateways "$GW" --prefix "$PREFIX" --home "$STATE"
else
  echo "服务装配：请以 root 执行 ${PREFIX}/bin/mynet install --gateways <wss://…> --prefix ${PREFIX} --home ${STATE}"
  echo "  （非 root 或非标准前缀时，本脚本只落文件，不登记服务）"
fi
echo "done: prefix=${PREFIX} state=${STATE_NOTE}"
