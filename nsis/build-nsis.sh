#!/bin/sh
# build-nsis.sh — 编 Windows 安装向导 .exe（E-7）
#
# 用法：
#   sh scripts/build-nsis.sh <windows 产物目录> [version]
#   例：sh nsis/build-nsis.sh ../mynet_agent/dist/mynet_agent_windows_amd64_v1.0.0 v1.0.0
#
# 产物：dist/mynet_agent_windows_<arch>_<version>.exe
#
# 依赖：makensis（NSIS 3.x）
#   macOS:   brew install makensis
#   Windows: https://nsis.sourceforge.io/Download
#   Linux:   apt install nsis / dnf install mingw32-nsis
set -eu

if [ $# -lt 1 ]; then
  echo "用法: sh build-nsis.sh <windows 产物目录> [version]" >&2
  exit 2
fi

SRCDIR=$1
VERSION=${2:-v0.0.0-dev}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

if ! command -v makensis >/dev/null 2>&1; then
  echo "✗ 找不到 makensis。装法见本脚本头注释。" >&2
  exit 1
fi

# 接受解压后的目录或直接指向 dist 下的文件夹
if [ -d "$SRCDIR" ]; then
  SRC=$(cd "$SRCDIR" && pwd)
else
  echo "✗ 目录不存在: $SRCDIR" >&2
  exit 1
fi

# kind 归属先于内容检查：目录归属错了就别再报「缺 mynet.exe」误导排查
case "$SRC" in
  *mynet_agent_windows_*) ;;
  *)
    echo "✗ $SRC 不是 windows 产物目录（build-nsis 只接受 mynet_agent_windows_*）" >&2
    exit 1
    ;;
esac

for b in mynet.exe mynetd.exe; do
  if [ ! -f "$SRC/$b" ]; then
    echo "✗ 缺 $SRC/$b —— 先在 mynet_agent 跑 make dist（含 windows）" >&2
    exit 1
  fi
done

# 来源记录（DC-3）：安装器必须携带与 agent dist 同源的 SOURCES.txt。
# 缺来源记录不产包 —— 否则装出去无法复核多仓 SHA。
SOURCES_TXT="$SRC/SOURCES.txt"
if [ ! -s "$SOURCES_TXT" ]; then
  echo "✗ 缺 $SOURCES_TXT —— agent dist 必须带 SOURCES.txt（build-sources.sh 产出）" >&2
  exit 1
fi

# 驱动依赖（随包分发）：wintun.dll 在仓内 nsis/vendor/（provenance/SHA 见
# nsis/wintun-provenance.md）。换文件必须同步该文档与本行的固定 SHA。
WINTUN_SHA256=e5da8447dc2c320edc0fc52fa01885c103de8c118481f683643cacc3220dafce
WINTUN_DLL="$SCRIPT_DIR/vendor/wintun/wintun.dll"
if [ ! -f "$WINTUN_DLL" ]; then
  echo "✗ 缺 $WINTUN_DLL（安装器随包分发的驱动依赖）" >&2
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
  got=$(sha256sum "$WINTUN_DLL" | awk '{print $1}')
else
  got=$(shasum -a 256 "$WINTUN_DLL" | awk '{print $1}')
fi
if [ "$got" != "$WINTUN_SHA256" ]; then
  echo "✗ wintun.dll SHA256 不匹配：期望 $WINTUN_SHA256，得到 $got" >&2
  exit 1
fi

base=$(basename "$SRC")
arch=$(printf '%s' "$base" | sed -n 's/^mynet_agent_windows_\([^_]*\)_.*/\1/p')
[ -n "$arch" ] || arch=amd64

# .nsi 里有中文（MessageBox / 注释），NSIS 3 只认「带 BOM 的 UTF-8」；
# 缺 BOM 会按 ANSI 解，轻则用户看到乱码弹窗，重则 makensis 直接
# 报 Bad text encoding 中止。这里前置断言，免得又静默漂回去。
NSI="$SCRIPT_DIR/mynet-agent.nsi"
if [ "$(head -c 3 "$NSI" | od -An -tx1 | tr -d ' \n')" != efbbbf ]; then
  echo "✗ $NSI 缺 UTF-8 BOM（含中文的 .nsi 必须带 BOM，否则 NSIS 按 ANSI 解）" >&2
  exit 1
fi

OUT_DIR="$ROOT/dist"
mkdir -p "$OUT_DIR"
OUTFILE="$OUT_DIR/mynet_agent_windows_${arch}_${VERSION}.exe"
SIDECAR="${OUTFILE}.SOURCES.txt"

# 先写 sidecar 再编包：任一步失败都不留可发布的半包（半成品 exe 也不留）。
# sidecar 供 check-installer-sources.sh 在无 7z 环境下复核来源。
cp "$SOURCES_TXT" "$SIDECAR"

makensis \
  -DWINTUN_DLL="$WINTUN_DLL" \
  -DVERSION="$VERSION" \
  -DARCH="$arch" \
  -DSRCDIR="$SRC" \
  -DOUTFILE="$OUTFILE" \
  "$NSI"

if [ ! -s "$OUTFILE" ]; then
  echo "✗ makensis 退出成功但没产出 $OUTFILE" >&2
  rm -f "$OUTFILE" "$SIDECAR"
  exit 1
fi

echo "✓ $OUTFILE"
echo "✓ $SIDECAR（来源 sidecar）"
ls -la "$OUTFILE" "$SIDECAR"
