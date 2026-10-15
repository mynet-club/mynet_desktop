#!/bin/sh
# check.sh — mynet_desktop 的真检查（lint / test）
#
# 为什么不是 echo 占位：门禁「无工具时跳过」等于没有门禁 —— 它把「环境没装好」
# 伪装成「检查通过」（AGENTS.md §2.6 的教训；mynet_ctl 的 pint/phpunit 曾这样假绿）。
# 所以这里只用**恒可用**的手段（sh -n / grep / install / stat）做真检查；
# 可选工具（shellcheck）缺失时打印明确的「已跳过」标记，绝不静默算过。
#
# 用法：sh scripts/check.sh [lint|test|all]
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-all}
pass=0; fail=0; skip=0
FAILED=""

ok()      { printf '  ✓ %s\n' "$1"; pass=$((pass+1)); }
bad()     { printf '  ✗ %s\n' "$1"; fail=$((fail+1)); FAILED="${FAILED} $1"; }
skipped() { printf '  ⚠ 已跳过：%s\n' "$1"; skip=$((skip+1)); }

# 取文件权限位（BSD 与 GNU 的 stat 语法不同 —— AGENTS.md §4 记过这个坑）
perm_of() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || echo ""
}

# ── lint ─────────────────────────────────────────────────────
lint_shell() {
  echo "▸ lint · shell"
  # 按 shebang 选检查器：bash 脚本里的 process substitution 等 bashism
  # 用 sh -n 检查会**假失败**（mynet_gnb 已实测撞到），误报多了门禁就会被绕过。
  # 覆盖 scripts/ + nsis/ + macos/（安装器脚本也是交付物，不是二等公民）。
  for f in "$ROOT"/scripts/*.sh "$ROOT"/nsis/*.sh "$ROOT"/macos/*.sh "$ROOT"/macos/scripts/*; do
    [ -f "$f" ] || continue
    case "$(head -1 "$f")" in
      *bash*) _i=bash ;;
      *)      _i="sh" ;;
    esac
    if ! command -v "$_i" >/dev/null 2>&1; then
      skipped "${_i} 不可用 —— $(basename "$f") 的语法本次未检查"
      continue
    fi
    if _err=$("$_i" -n "$f" 2>&1); then
      ok "${_i} -n $(basename "$f")"
    else
      bad "${_i} -n $(basename "$f")：$(printf '%s\n' "$_err" | head -1)"
    fi
  done

  if command -v shellcheck >/dev/null 2>&1; then
    _n=$(shellcheck "$ROOT"/scripts/*.sh 2>&1 | grep -c '^In ' || true)
    if [ "$_n" -eq 0 ]; then ok "shellcheck 无告警"; else bad "shellcheck 有 ${_n} 处告警"; fi
  else
    skipped "shellcheck 未安装 —— 语法已由上面的 -n 覆盖，引用/风格类问题本次未检查"
  fi
}

# Linux 安装契约：薄壳 —— unit/服务登记只归 `mynet install`（合同 §1）。
lint_linux() {
  echo "▸ lint · Linux 安装器（薄壳委托）"
  if [ -f "$ROOT/systemd/mynetd.service" ]; then
    bad "systemd/mynetd.service 应已删除（unit 由 mynet install 内嵌写出）"
  else
    ok "不自带 systemd unit"
  fi
  _sh="$ROOT/scripts/install-linux.sh"
  if grep -q 'mynet\" install\|bin/mynet\" install' "$_sh" 2>/dev/null; then
    ok "install-linux.sh 委托 mynet install 装配服务"
  else
    bad "install-linux.sh 未委托 mynet install（自拷 unit = 违反单一 owner）"
  fi
  if grep -q 'systemd/mynetd.service' "$_sh" 2>/dev/null; then
    bad "install-linux.sh 仍在自拷 unit"
  else
    ok "install-linux.sh 不自拷 unit"
  fi
}

lint_macos() {
  echo "▸ lint · macOS 安装器（薄壳委托）"
  _post="$ROOT/macos/scripts/postinstall"
  _pre="$ROOT/macos/scripts/preinstall"
  _pkg="$ROOT/macos/build-pkg.sh"

  # 服务登记唯一 owner 是 mynet install：pkg 不自带 plist（根 launchd/ 已退役）
  if ls "$ROOT"/launchd/*.plist >/dev/null 2>&1; then
    bad "根 launchd/ 仍有 plist —— 登记归 mynet install，pkg 不得自带"
  else
    ok "pkg 不自带 launchd plist"
  fi

  if grep -q 'mynet" install\|mynet install' "$_post" 2>/dev/null; then
    ok "postinstall 委托 mynet install 装配服务"
  else
    bad "postinstall 未调用 mynet install（自建登记 = 违反单一 owner）"
  fi

  if grep -q 'com.mynet.mynetd' "$_pre" 2>/dev/null && grep -q 'club.mynet.mynetd' "$_pre" 2>/dev/null; then
    ok "preinstall 同时停 legacy + 新 label"
  else
    bad "preinstall 未同时停 club.mynet.mynetd 与 com.mynet.mynetd"
  fi

  if grep -q 'PAYLOAD/Library/LaunchDaemons' "$_pkg" 2>/dev/null; then
    bad "build-pkg.sh 仍在 payload 里放 plist（应由 mynet install 写）"
  else
    ok "build-pkg.sh 不落 plist"
  fi
}

# Windows 安装器契约：薄壳 —— **服务登记只归 `mynet install`**（合同 §1）。
lint_nsis() {
  echo "▸ lint · Windows 安装器（薄壳委托）"
  _nsi="$ROOT/nsis/mynet-agent.nsi"
  if [ -f "$ROOT/nsis/service.ps1" ]; then
    bad "nsis/service.ps1 应已删除（登记归 mynet install，不设并行实现）"
  else
    ok "无 service.ps1 并行实现"
  fi
  if grep -q 'schtasks /create\|schtasks /delete' "$_nsi" 2>/dev/null; then
    bad "nsi 仍自建计划任务（登记应委托 mynet install）"
  else
    ok "nsi 不自建计划任务"
  fi
  if grep -q '" install --gateways' "$_nsi" 2>/dev/null; then
    ok "nsi 委托 mynet install 装配服务"
  else
    bad "nsi 未调用 mynet install（自建登记 = 违反单一 owner）"
  fi
  if [ -f "$ROOT/nsis/vendor/wintun/wintun.dll" ]; then
    ok "随包 DLL 在仓（nsis/vendor/wintun）"
  else
    bad "缺 nsis/vendor/wintun/wintun.dll（安装器要随包分发它）"
  fi
  if [ -f "$ROOT/.guard-c4-allow" ]; then
    ok "有 .guard-c4-allow（DLL 入库白名单，过 guard C4）"
  else
    bad "缺 .guard-c4-allow —— DLL 会被 guard C4 拦下"
  fi
  if grep -q 'wintun.dll' "$_nsi" 2>/dev/null && grep -q 'driver\\gnb\\bin' "$_nsi" 2>/dev/null; then
    ok "nsi 内置 wintun.dll 到 gnb.exe 同目录"
  else
    bad "nsi 未把 wintun.dll 落到 gnb.exe 同目录（缺 DLL 会崩）"
  fi
  if grep -q '" uninstall --home' "$_nsi" 2>/dev/null; then
    ok "nsi 卸载委托 mynet uninstall"
  else
    bad "nsi 卸载未委托 mynet uninstall（会留登记残留）"
  fi
}

# ── test ─────────────────────────────────────────────────────
# 行为测试：install-linux.sh 是否真的尊重 PREFIX/STATE（R3-5 的判据），
# 以及**缺产物时是否失败**（此前它退出码 0、什么都不装、还打印 done）。
#
# ⚠️ 坏路径用例会临时搬走 dist/。此前它直接 rm -rf，把真实安装器
#    产物一并抹掉（实测踩过：check 刚过，dist 就空了）。现在先 mv 走、
#    测完必还原；还原失败要炸出来，不能装没发生。
test_install() {
  echo "▸ test · install-linux.sh 行为"
  _t=$(mktemp -d)
  _dist="$ROOT/dist/mynet_agent_linux_amd64"
  _backup="$ROOT/.dist-test-backup.$$"
  _had_dist=0
  [ -d "$ROOT/dist" ] && _had_dist=1

  cleanup() {
    rm -rf "$_t"
    # 还原 dist：测前有就还回去，测前没有就别留垃圾
    if [ -d "$_backup" ]; then
      rm -rf "$ROOT/dist"
      mv "$_backup" "$ROOT/dist" || echo "  ✗ dist 还原失败：$_backup" >&2
    elif [ "$_had_dist" -eq 0 ]; then
      rm -rf "$ROOT/dist"
    fi
  }
  trap cleanup EXIT INT TERM

  # ── 好路径：有产物 → 装进 PREFIX，权限 0755
  mkdir -p "$_dist"
  printf '#!/bin/sh\necho fake-mynet\n' > "$_dist/mynet"
  printf '#!/bin/sh\necho fake-mynetd\n' > "$_dist/mynetd"
  _out=$(PREFIX="$_t/p" STATE="$_t/s" sh "$ROOT/scripts/install-linux.sh" 2>&1)
  _rc=$?
  if [ "$_rc" -eq 0 ]; then ok "有产物时安装成功（退出码 0）"; else bad "有产物时安装失败（退出码 ${_rc}）：$(printf '%s' "$_out" | head -1)"; fi
  for b in mynet mynetd; do
    if [ -f "$_t/p/bin/$b" ]; then
      _perm=$(perm_of "$_t/p/bin/$b")
      if [ "$_perm" = 755 ]; then ok "${b} 已装入 PREFIX/bin 且权限 0755"
      else bad "${b} 权限是 ${_perm}，应为 755"; fi
    else
      bad "${b} 未被装进 PREFIX/bin"
    fi
  done
  if [ -d "$_t/p/conf" ]; then ok "PREFIX/conf 已创建"; else bad "PREFIX/conf 未创建"; fi
  if [ -d "$_t/s" ]; then ok "STATE 可写时确实被创建"; else bad "STATE 未被创建"; fi

  # ── STATE 不可写：必须**如实说明**，不能假装成功
  mkdir -p "$_t/ro" && chmod 500 "$_t/ro"
  _out=$(PREFIX="$_t/p2" STATE="$_t/ro/sub" sh "$ROOT/scripts/install-linux.sh" 2>&1)
  case "$_out" in
    *未创建*) ok "STATE 创建不了时如实标注（不再假装成功）" ;;
    *)        bad "STATE 创建不了却未标注；输出：$(printf '%s' "$_out" | tail -1)" ;;
  esac
  chmod 700 "$_t/ro"

  # ── 坏路径：无产物 → 必须失败，且说清缺什么
  # 先清掉假产物，再把真实 dist 搬走（不是 rm）：测完 cleanup 会还回来
  rm -rf "$_dist"
  if [ -d "$ROOT/dist" ]; then
    mv "$ROOT/dist" "$_backup"
  fi
  _out=$(PREFIX="$_t/p3" STATE="$_t/s3" sh "$ROOT/scripts/install-linux.sh" 2>&1)
  _rc=$?
  if [ "$_rc" -ne 0 ]; then ok "缺产物时失败（退出码 ${_rc}），不再静默装空布局"
  else bad "缺产物时仍退出码 0 —— 静默空安装（V2-9 同源缺陷）"; fi
  case "$_out" in
    *找不到*) ok "缺产物时报错指明了缺哪个文件" ;;
    *)        bad "缺产物时未说明缺什么；输出：$(printf '%s' "$_out" | head -1)" ;;
  esac
  if [ -f "$_t/p3/bin/mynet" ] || [ -f "$_t/p3/bin/mynetd" ]; then
    bad "缺产物时仍写入了 PREFIX/bin"
  else
    ok "缺产物时没有留下半套布局"
  fi

  cleanup
  trap - EXIT INT TERM
}

# 安装器来源复核行为（DC-3）：check-installer-sources.sh 必须
#   ① 一致通过 ② 不一致拒绝 ③ 取不到 SOURCES 拒绝（不能静默放过）
#   ④ 归档类型拒绝（归档走 check-package-sources，不许混用）
test_installer_sources() {
  echo "▸ test · 安装器来源复核（DC-3）"
  _t=$(mktemp -d)
  trap 'rm -rf "$_t"' EXIT INT TERM

  _exp="$_t/expected.txt"
  printf 'format=1\nagent_sha=fixture-a\ngui_sha=fixture-g\n' > "$_exp"
  _other="$_t/other.txt"
  printf 'format=1\nagent_sha=different\ngui_sha=fixture-g\n' > "$_other"

  # ① 目录形态：一致 → 过
  mkdir -p "$_t/dist_ok"
  cp "$_exp" "$_t/dist_ok/SOURCES.txt"
  if _out=$(sh "$ROOT/scripts/check-installer-sources.sh" "$_t/dist_ok" "$_exp" 2>&1); then
    ok "目录 SOURCES 一致时通过"
  else
    bad "目录 SOURCES 一致却失败：$(printf '%s' "$_out" | head -1)"
  fi

  # ② 目录形态：不一致 → 拒
  mkdir -p "$_t/dist_bad"
  cp "$_other" "$_t/dist_bad/SOURCES.txt"
  if _out=$(sh "$ROOT/scripts/check-installer-sources.sh" "$_t/dist_bad" "$_exp" 2>&1); then
    bad "目录 SOURCES 不一致却通过"
  else
    ok "目录 SOURCES 不一致时拒绝"
  fi

  # ③ 目录缺 SOURCES → 拒
  mkdir -p "$_t/dist_empty"
  if _out=$(sh "$ROOT/scripts/check-installer-sources.sh" "$_t/dist_empty" "$_exp" 2>&1); then
    bad "目录缺 SOURCES 却通过"
  else
    ok "目录缺 SOURCES 时拒绝"
  fi

  # ④ exe + sidecar：一致 → 过
  printf 'MZ-fake-installer' > "$_t/mynet_agent_windows_amd64_v0.0.0-test.exe"
  cp "$_exp" "$_t/mynet_agent_windows_amd64_v0.0.0-test.exe.SOURCES.txt"
  if _out=$(sh "$ROOT/scripts/check-installer-sources.sh" "$_t/mynet_agent_windows_amd64_v0.0.0-test.exe" "$_exp" 2>&1); then
    ok "exe sidecar 一致时通过"
  else
    bad "exe sidecar 一致却失败：$(printf '%s' "$_out" | head -1)"
  fi

  # ⑤ exe + sidecar 不一致 → 拒
  cp "$_other" "$_t/mynet_agent_windows_amd64_v0.0.0-test.exe.SOURCES.txt"
  if _out=$(sh "$ROOT/scripts/check-installer-sources.sh" "$_t/mynet_agent_windows_amd64_v0.0.0-test.exe" "$_exp" 2>&1); then
    bad "exe sidecar 不一致却通过"
  else
    ok "exe sidecar 不一致时拒绝"
  fi

  # ⑥ exe 无 sidecar 且取不到内嵌 SOURCES → 拒（不能静默放过）
  rm -f "$_t/mynet_agent_windows_amd64_v0.0.0-test.exe.SOURCES.txt"
  if _out=$(sh "$ROOT/scripts/check-installer-sources.sh" "$_t/mynet_agent_windows_amd64_v0.0.0-test.exe" "$_exp" 2>&1); then
    # 若本机有 7z 且假 exe 里没有 SOURCES，也应失败；若 7z 把假 exe 解出点什么仍找不到 SOURCES，同样失败。
    # 只有「解出且一致」才过 —— 假 exe 不可能走到那条路，所以这里过 = 缺陷。
    bad "exe 无来源记录却通过（复核不了不算通过）"
  else
    ok "exe 取不到 SOURCES 时拒绝（不静默放过）"
  fi

  # ⑦ kind 判定：归档可核（解出 SOURCES）；未知扩展名拒绝
  # 归档好路径：内含 SOURCES → 过
  _tgz_dir="$_t/mynet_agent_linux_amd64_v0.0.0-test"
  mkdir -p "$_tgz_dir"
  cp "$_exp" "$_tgz_dir/SOURCES.txt"
  tar -czf "$_t/mynet_agent_linux_amd64_v0.0.0-test.tgz" -C "$_t" "mynet_agent_linux_amd64_v0.0.0-test"
  if _out=$(sh "$ROOT/scripts/check-installer-sources.sh" "$_t/mynet_agent_linux_amd64_v0.0.0-test.tgz" "$_exp" 2>&1); then
    ok "归档 .tgz 内含 SOURCES 时通过"
  else
    bad "归档 .tgz 内含 SOURCES 却失败：$(printf '%s' "$_out" | head -1)"
  fi
  # 归档 SOURCES 不一致 → 拒
  cp "$_other" "$_tgz_dir/SOURCES.txt"
  tar -czf "$_t/mynet_agent_linux_amd64_v0.0.0-test.tgz" -C "$_t" "mynet_agent_linux_amd64_v0.0.0-test"
  if _out=$(sh "$ROOT/scripts/check-installer-sources.sh" "$_t/mynet_agent_linux_amd64_v0.0.0-test.tgz" "$_exp" 2>&1); then
    bad "归档 SOURCES 不一致却通过"
  else
    ok "归档 SOURCES 不一致时拒绝"
  fi
  # 未知扩展名 → 拒（不猜 kind）
  printf 'unknown' > "$_t/mystery.bin"
  if _out=$(sh "$ROOT/scripts/check-installer-sources.sh" "$_t/mystery.bin" "$_exp" 2>&1); then
    bad "未知扩展名却通过（应拒绝、不猜 kind）"
  else
    ok "未知扩展名时拒绝（不猜 kind）"
  fi

  # ⑧ 期望 SOURCES 为空 → 拒
  : > "$_t/empty-expected.txt"
  if _out=$(sh "$ROOT/scripts/check-installer-sources.sh" "$_t/dist_ok" "$_t/empty-expected.txt" 2>&1); then
    bad "期望 SOURCES 为空却通过"
  else
    ok "期望 SOURCES 为空时拒绝"
  fi

  trap - EXIT INT TERM
  rm -rf "$_t"
}

# 安装器构建脚本拒绝路径（DC-3）：缺 SOURCES / kind 错配必须失败且不产半包
test_installer_build_rejects() {
  echo "▸ test · 安装器构建脚本拒绝路径（DC-3）"
  _t=$(mktemp -d)
  trap 'rm -rf "$_t"' EXIT INT TERM

  # ① build-nsis：缺 SOURCES → 拒，不产包
  _w="$_t/mynet_agent_windows_amd64_v0.0.0-test"
  mkdir -p "$_w"
  printf 'MZ-fake' > "$_w/mynet.exe"
  printf 'MZ-fake' > "$_w/mynetd.exe"
  if _out=$(sh "$ROOT/nsis/build-nsis.sh" "$_w" v0.0.0-test 2>&1); then
    bad "build-nsis 缺 SOURCES 却成功"
  else
    ok "build-nsis 缺 SOURCES 时拒绝"
  fi
  if ls "$ROOT"/dist/mynet_agent_windows_*v0.0.0-test* >/dev/null 2>&1; then
    bad "build-nsis 缺 SOURCES 仍产出半包"
    rm -f "$ROOT"/dist/mynet_agent_windows_*v0.0.0-test*
  else
    ok "build-nsis 缺 SOURCES 不产半包"
  fi

  # ② build-nsis：kind 错配（darwin 目录）→ 拒，报 kind 而非缺二进制
  _d="$_t/mynet_agent_darwin_arm64_v0.0.0-test"
  mkdir -p "$_d"
  printf 'fake' > "$_d/mynet"
  printf 'fake' > "$_d/mynetd"
  printf 'format=1\nagent_sha=x\n' > "$_d/SOURCES.txt"
  _out=$(sh "$ROOT/nsis/build-nsis.sh" "$_d" v0.0.0-test 2>&1) || true
  case "$_out" in
    *windows*) ok "build-nsis kind 错配时报 windows 产物目录" ;;
    *)        bad "build-nsis kind 错配提示不对：$(printf '%s' "$_out" | head -1)" ;;
  esac

  # ③ build-pkg：缺 SOURCES → 拒
  _d2="$_t/mynet_agent_darwin_arm64_v0.0.0-test2"
  mkdir -p "$_d2"
  printf 'fake' > "$_d2/mynet"
  printf 'fake' > "$_d2/mynetd"
  if _out=$(sh "$ROOT/macos/build-pkg.sh" "$_d2" v0.0.0-test 2>&1); then
    bad "build-pkg 缺 SOURCES 却成功"
  else
    ok "build-pkg 缺 SOURCES 时拒绝"
  fi

  # ④ build-pkg：kind 错配（windows 目录）→ 拒，报 kind
  printf 'format=1\nagent_sha=x\n' > "$_w/SOURCES.txt"
  _out=$(sh "$ROOT/macos/build-pkg.sh" "$_w" v0.0.0-test 2>&1) || true
  case "$_out" in
    *darwin*) ok "build-pkg kind 错配时报 darwin 产物目录" ;;
    *)        bad "build-pkg kind 错配提示不对：$(printf '%s' "$_out" | head -1)" ;;
  esac

  # ⑤ build-dmg：缺 sidecar → 拒
  printf 'fake-pkg' > "$_t/mynet_agent_darwin_arm64_v0.0.0-test.pkg"
  if _out=$(sh "$ROOT/macos/build-dmg.sh" "$_t/mynet_agent_darwin_arm64_v0.0.0-test.pkg" 2>&1); then
    bad "build-dmg 缺 sidecar 却成功"
  else
    ok "build-dmg 缺 sidecar 时拒绝"
  fi

  trap - EXIT INT TERM
  rm -rf "$_t"
}

lint_installers() {
  echo "▸ lint · 安装器骨架（E-7）"
  for f in \
    "$ROOT/nsis/mynet-agent.nsi" \
    "$ROOT/macos/build-pkg.sh" \
    "$ROOT/macos/build-dmg.sh" \
    "$ROOT/macos/scripts/preinstall" \
    "$ROOT/macos/scripts/postinstall" \
    "$ROOT/docs/INSTALL.md"
  do
    if [ -f "$f" ]; then ok "存在 $(basename "$f")"; else bad "缺 $f"; fi
  done

  # NSI 里不能再用 EnVar 插件（makensis 开箱没有，装了 NSIS 也可能编不过）
  if grep -q 'EnVar::' "$ROOT/nsis/mynet-agent.nsi" 2>/dev/null; then
    bad "nsi 引用了 EnVar 插件（应改用 nsExec + PowerShell）"
  else
    ok "nsi 无 EnVar 插件依赖"
  fi

  # postinstall 缺产物必须 exit 非 0（V2-9 同源）
  if grep -q 'exit 1' "$ROOT/macos/scripts/postinstall" 2>/dev/null; then
    ok "postinstall 缺产物会失败退出"
  else
    bad "postinstall 没有失败路径（缺产物会静默装空壳）"
  fi
}

# 安装器来源契约（DC-3）：构建脚本必须要求 SOURCES.txt、嵌入包内、写 sidecar。
lint_installer_sources() {
  echo "▸ lint · 安装器来源记录与复核（DC-3）"

  if [ -f "$ROOT/scripts/check-installer-sources.sh" ]; then
    ok "存在 check-installer-sources.sh"
  else
    bad "缺 scripts/check-installer-sources.sh（安装器来源复核）"
  fi

  # build-nsis.sh：要求 SOURCES.txt + 写 sidecar
  _nsis_build="$ROOT/nsis/build-nsis.sh"
  if grep -q 'SOURCES\.txt' "$_nsis_build" 2>/dev/null; then
    ok "build-nsis.sh 引用 SOURCES.txt"
  else
    bad "build-nsis.sh 未引用 SOURCES.txt（安装器须带来源记录）"
  fi
  if grep -q 'SOURCES_TXT=' "$_nsis_build" 2>/dev/null || grep -q 'SOURCES\.txt' "$_nsis_build" 2>/dev/null; then
    if grep -q 'SIDECAR\|SOURCES\.txt"' "$_nsis_build" 2>/dev/null; then
      ok "build-nsis.sh 写来源 sidecar"
    else
      bad "build-nsis.sh 未写来源 sidecar（无 7z 环境无法复核）"
    fi
  fi
  # NSI 必须把 SOURCES.txt 打进包内（无 /nonfatal：缺则编译失败）
  _nsi="$ROOT/nsis/mynet-agent.nsi"
  if grep -q 'SOURCES\.txt' "$_nsi" 2>/dev/null; then
    ok "nsi 嵌入 SOURCES.txt"
  else
    bad "nsi 未嵌入 SOURCES.txt（装完无法核对多仓 SHA）"
  fi

  # build-pkg.sh：要求 SOURCES.txt + 落 payload + sidecar
  _pkg_build="$ROOT/macos/build-pkg.sh"
  if grep -q 'SOURCES\.txt' "$_pkg_build" 2>/dev/null; then
    ok "build-pkg.sh 引用 SOURCES.txt"
  else
    bad "build-pkg.sh 未引用 SOURCES.txt"
  fi
  if grep -q 'share/SOURCES\.txt\|SOURCES\.txt' "$_pkg_build" 2>/dev/null; then
    ok "build-pkg.sh 嵌入 SOURCES.txt"
  else
    bad "build-pkg.sh 未嵌入 SOURCES.txt"
  fi

  # build-dmg.sh：要求 sidecar + 内嵌
  _dmg_build="$ROOT/macos/build-dmg.sh"
  if grep -q 'SOURCES\.txt' "$_dmg_build" 2>/dev/null; then
    ok "build-dmg.sh 引用 SOURCES.txt"
  else
    bad "build-dmg.sh 未引用 SOURCES.txt"
  fi

  # kind 归属：构建脚本必须拒绝错误平台目录
  if grep -q 'mynet_agent_windows_' "$_nsis_build" 2>/dev/null; then
    ok "build-nsis.sh 校验 windows 产物目录（kind 归属）"
  else
    bad "build-nsis.sh 未校验 windows 产物目录（可把 darwin 目录当安装器源）"
  fi
  if grep -q 'mynet_agent_darwin_' "$_pkg_build" 2>/dev/null; then
    ok "build-pkg.sh 校验 darwin 产物目录（kind 归属）"
  else
    bad "build-pkg.sh 未校验 darwin 产物目录"
  fi
}

# ── 调度 ─────────────────────────────────────────────────────
case "$MODE" in
  lint) lint_shell; lint_linux; lint_macos; lint_nsis; lint_installers; lint_installer_sources ;;
  test) test_install; test_installer_sources; test_installer_build_rejects ;;
  all)  lint_shell; lint_linux; lint_macos; lint_nsis; lint_installers; lint_installer_sources; test_install; test_installer_sources; test_installer_build_rejects ;;
  *)    echo "用法：sh scripts/check.sh [lint|test|all]"; exit 2 ;;
esac

echo
printf 'desktop 检查：%s 通过 / %s 失败 / %s 已跳过\n' "$pass" "$fail" "$skip"
if [ "$skip" -ne 0 ]; then
  echo "  ⚠ 有 ${skip} 项被跳过 —— 跳过不是通过，缺的工具装上后需重跑"
fi
[ "$fail" -eq 0 ] || { printf '失败项:%s\n' "$FAILED"; exit 1; }
exit 0
