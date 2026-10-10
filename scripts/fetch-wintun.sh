#!/bin/sh
# fetch-wintun.sh — 把 wintun.dll 放入 NSIS 的 SRCDIR，并按固定 SHA256 校验。
#
# 为什么不在仓里存 DLL：guard C4 把 *.dll 视为产物后缀（源码仓只提交源码）。
# 这里按「钉死 SHA + 来源」取件，成品安装器仍自带 DLL。provenance 见
# nsis/wintun-provenance.md。
#
# 用法：
#   sh scripts/fetch-wintun.sh <SRCDIR> [本地副本路径 | 直链 URL]
#   或经环境变量给来源：
#     WINTUN_DLL=/path/to/wintun.dll  sh scripts/fetch-wintun.sh <SRCDIR>
#     WINTUN_URL=https://…/wintun.dll sh scripts/fetch-wintun.sh <SRCDIR>
set -eu

# 固定 SHA256（nsis/wintun-provenance.md 的 SSOT，改这里必须同步改那份文档）
WINTUN_SHA256=e5da8447dc2c320edc0fc52fa01885c103de8c118481f683643cacc3220dafce

if [ $# -lt 1 ]; then
  echo "用法: sh scripts/fetch-wintun.sh <SRCDIR> [本地副本路径 | URL]" >&2
  exit 2
fi
SRCDIR=$1
SRC=${2:-${WINTUN_DLL:-${WINTUN_URL:-}}}
if [ -z "$SRC" ]; then
  echo "✗ 未给来源：传第 2 参，或设 WINTUN_DLL=<本地副本> / WINTUN_URL=<直链>" >&2
  echo "  （provenance 与 SHA 见 nsis/wintun-provenance.md）" >&2
  exit 2
fi
if [ ! -d "$SRCDIR" ]; then
  echo "✗ SRCDIR 不存在: $SRCDIR" >&2
  exit 1
fi

dst="$SRCDIR/wintun.dll"
case "$SRC" in
  http://*|https://*)
    echo "▸ 下载 wintun.dll ← $SRC"
    curl -fL --retry 3 -o "$dst" "$SRC" || { echo "✗ 下载失败" >&2; exit 1; }
    ;;
  *)
    [ -f "$SRC" ] || { echo "✗ 本地副本不存在: $SRC" >&2; exit 1; }
    cp "$SRC" "$dst"
    ;;
esac

# 兼容 GNU/Linux(CI) 与 BSD/macOS 取摘要
if command -v sha256sum >/dev/null 2>&1; then
  got=$(sha256sum "$dst" | awk '{print $1}')
else
  got=$(shasum -a 256 "$dst" | awk '{print $1}')
fi
if [ "$got" != "$WINTUN_SHA256" ]; then
  echo "✗ wintun.dll SHA256 不匹配：期望 $WINTUN_SHA256，得到 $got" >&2
  rm -f "$dst"
  exit 1
fi
echo "✓ wintun.dll 就位且校验通过: $dst"
