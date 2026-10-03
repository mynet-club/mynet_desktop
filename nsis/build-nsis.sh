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

for b in mynet.exe mynetd.exe; do
  if [ ! -f "$SRC/$b" ]; then
    echo "✗ 缺 $SRC/$b —— 先在 mynet_agent 跑 make dist（含 windows）" >&2
    exit 1
  fi
done

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

makensis \
  -DVERSION="$VERSION" \
  -DARCH="$arch" \
  -DSRCDIR="$SRC" \
  -DOUTFILE="$OUTFILE" \
  "$NSI"

if [ ! -s "$OUTFILE" ]; then
  echo "✗ makensis 退出成功但没产出 $OUTFILE" >&2
  exit 1
fi

echo "✓ $OUTFILE"
ls -la "$OUTFILE"
