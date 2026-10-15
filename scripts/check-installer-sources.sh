#!/bin/sh
# check-installer-sources.sh PACKAGE_OR_DIR EXPECTED_SOURCES
#
# 安装器/归档来源复核（DC-3）：安装包与自更新归档都必须携带与期望逐字一致的
# SOURCES.txt，否则拒绝 —— 「HTTP 200 / 文件存在」不能证明多仓来源一致。
#
# 用法：
#   sh scripts/check-installer-sources.sh dist/mynet_agent_windows_amd64_v1.0.0.exe \
#       ../mynet_agent/dist/mynet_agent_windows_amd64_v1.0.0/SOURCES.txt
#   sh scripts/check-installer-sources.sh dist/mynet_agent_darwin_arm64_v1.0.0.pkg \
#       ../mynet_agent/dist/mynet_agent_darwin_arm64_v1.0.0/SOURCES.txt
#   sh scripts/check-installer-sources.sh dist/mynet_agent_linux_amd64_v1.0.0.tgz \
#       ../mynet_agent/dist/mynet_agent_linux_amd64_v1.0.0/SOURCES.txt
#
# kind 判定（拒绝用错复核路径）：
#   archive  (.tgz/.zip/.tar.gz) —— 解归档取 <name>/SOURCES.txt
#   installer(.exe/.pkg/.dmg)    —— 解包内/旁 sidecar 取 SOURCES.txt
#   目录                        —— 直接读 <dir>/SOURCES.txt（与 pack.sh 同源输入）
#   其余                        —— 拒绝（不猜 kind）
#
# 取不到 SOURCES 一律失败（exit 1）—— 「复核不了」不是「复核通过」。
set -eu

if [ $# -ne 2 ]; then
  echo "用法: sh check-installer-sources.sh <安装包|归档|产物目录> <期望 SOURCES.txt>" >&2
  exit 2
fi

target=$1
expected=$2

if [ ! -f "$expected" ]; then
  echo "✗ 期望的 SOURCES.txt 不存在: $expected" >&2
  exit 1
fi
if [ ! -s "$expected" ]; then
  echo "✗ 期望的 SOURCES.txt 为空: $expected" >&2
  exit 1
fi

if [ -d "$target" ]; then
  # 产物目录形态（与 pack.sh 输入同源）
  src="$target/SOURCES.txt"
  if [ ! -s "$src" ]; then
    echo "✗ 产物目录缺 SOURCES.txt: $target" >&2
    exit 1
  fi
  if cmp -s "$src" "$expected"; then
    echo "✓ SOURCES 一致（目录）: $target"
    exit 0
  fi
  echo "✗ SOURCES 不一致（目录）: $target" >&2
  echo "  期望: $expected" >&2
  echo "  实际: $src" >&2
  exit 1
fi

if [ ! -f "$target" ]; then
  echo "✗ 安装包不存在: $target" >&2
  exit 1
fi
if [ ! -s "$target" ]; then
  echo "✗ 安装包为空: $target" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
found=""

case "$target" in
  *.tgz|*.tar.gz)
    # 自更新归档：SOURCES 在 <basename>/SOURCES.txt
    base=$(basename "$target")
    base=${base%.tgz}
    base=${base%.tar.gz}
    if tar -xzOf "$target" "${base}/SOURCES.txt" > "$tmp/from-archive.txt" 2>/dev/null; then
      found="$tmp/from-archive.txt"
    fi
    ;;
  *.zip)
    base=$(basename "$target")
    base=${base%.zip}
    if unzip -p "$target" "${base}/SOURCES.txt" > "$tmp/from-archive.txt" 2>/dev/null; then
      found="$tmp/from-archive.txt"
    fi
    ;;
  *.pkg)
    # xar 是 pkg 的原生容器工具；展开后 payload 在 Payload 子树。
    if ! command -v xar >/dev/null 2>&1; then
      echo "✗ 需要 xar 解 .pkg（macOS 自带；Linux 装 xar）" >&2
      exit 1
    fi
    mkdir -p "$tmp/expand"
    if ! xar -xf "$target" -C "$tmp/expand" 2>/dev/null; then
      echo "✗ xar 解不开 $target" >&2
      exit 1
    fi
    # pkg 展开后 SOURCES 可能在 Payload 的 cpio 里，或与 Payload 同级。
    # 先找展开树里的 SOURCES.txt；找不到再解 Payload cpio。
    found=$(find "$tmp/expand" -name 'SOURCES.txt' -type f 2>/dev/null | head -1)
    if [ -z "$found" ]; then
      payload=$(find "$tmp/expand" -name 'Payload' -type f 2>/dev/null | head -1)
      if [ -n "$payload" ]; then
        mkdir -p "$tmp/payload"
        # pkg 的 Payload 是 gzip+cpio 或纯 cpio
        if gzip -dc "$payload" 2>/dev/null | (cd "$tmp/payload" && cpio -idm 2>/dev/null); then
          found=$(find "$tmp/payload" -name 'SOURCES.txt' -type f 2>/dev/null | head -1)
        elif (cd "$tmp/payload" && cpio -idm < "$payload" 2>/dev/null); then
          found=$(find "$tmp/payload" -name 'SOURCES.txt' -type f 2>/dev/null | head -1)
        fi
      fi
    fi
    ;;
  *.dmg)
    # 优先 sidecar（构建时写在 dmg 旁），其次挂载 dmg 内层。
    sidecar="${target}.SOURCES.txt"
    if [ -s "$sidecar" ]; then
      found=$sidecar
    elif command -v hdiutil >/dev/null 2>&1; then
      attach=$(hdiutil attach -nobrowse -readonly "$target" 2>/dev/null | awk 'NF{print $NF}' | tail -1)
      if [ -n "$attach" ] && [ -d "$attach" ]; then
        # 路径可能含空格，用 find 而不是拼接
        found=$(find "$attach" -name 'SOURCES.txt' -type f 2>/dev/null | head -1)
        # 复制出来再卸载
        if [ -n "$found" ] && [ "$found" != "$sidecar" ]; then
          cp "$found" "$tmp/from-dmg.txt"
          found="$tmp/from-dmg.txt"
        fi
        hdiutil detach "$attach" >/dev/null 2>&1 || true
      fi
    fi
    if [ -z "$found" ]; then
      echo "✗ 取不到 dmg 内/旁的 SOURCES.txt: $target" >&2
      echo "  期望 sidecar ${target}.SOURCES.txt 存在，或本机有 hdiutil" >&2
      exit 1
    fi
    ;;
  *.exe)
    sidecar="${target}.SOURCES.txt"
    if [ -s "$sidecar" ]; then
      found=$sidecar
    elif command -v 7z >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1; then
      z7=$(command -v 7z 2>/dev/null || command -v 7za)
      # NSIS 自解压可被 7z 列出/解开
      if "$z7" x -y -o"$tmp/nsis" "$target" >/dev/null 2>&1; then
        found=$(find "$tmp/nsis" -name 'SOURCES.txt' -type f 2>/dev/null | head -1)
      fi
    fi
    if [ -z "$found" ]; then
      echo "✗ 取不到 exe 内/旁的 SOURCES.txt: $target" >&2
      echo "  期望 sidecar ${target}.SOURCES.txt 存在，或本机有 7z" >&2
      echo "  「复核不了」不算通过 —— 拒绝静默跳过" >&2
      exit 1
    fi
    ;;
  *.ipk)
    # OpenWrt 包：ar 归档，SOURCES 可能不在内（ipk 走 build_openwrt.yml）。
    # 有 sidecar 就核，没有就明确拒绝（不猜）。
    sidecar="${target}.SOURCES.txt"
    if [ -s "$sidecar" ]; then
      found=$sidecar
    else
      echo "✗ ipk 无 sidecar 且不支持内嵌 SOURCES 复核: $target" >&2
      echo "  期望 ${target}.SOURCES.txt" >&2
      exit 1
    fi
    ;;
  *)
    echo "✗ 不支持的包类型: $target" >&2
    echo "  支持：.tgz/.tar.gz/.zip（归档）.exe/.pkg/.dmg（安装器）.ipk（sidecar）或产物目录" >&2
    exit 1
    ;;
esac

if [ -z "$found" ] || [ ! -s "$found" ]; then
  echo "✗ 包内没有 SOURCES.txt: $target" >&2
  exit 1
fi

if cmp -s "$found" "$expected"; then
  echo "✓ SOURCES 一致: $target"
  exit 0
fi

echo "✗ SOURCES 不一致: $target" >&2
echo "  期望: $expected" >&2
echo "  实际: $found" >&2
echo "  --- diff (期望 vs 实际) ---" >&2
diff -u "$expected" "$found" >&2 || true
exit 1
