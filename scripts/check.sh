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
  for f in "$ROOT"/scripts/*.sh; do
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

lint_systemd() {
  echo "▸ lint · systemd unit"
  _u="$ROOT/systemd/mynetd.service"
  if [ ! -f "$_u" ]; then bad "缺 systemd/mynetd.service"; return; fi

  for sec in '[Unit]' '[Service]' '[Install]'; do
    if grep -qF "$sec" "$_u"; then ok "unit 有 ${sec} 段"; else bad "unit 缺 ${sec} 段"; fi
  done
  for key in ExecStart Restart WantedBy; do
    if grep -q "^${key}=" "$_u"; then ok "unit 有 ${key}="; else bad "unit 缺 ${key}="; fi
  done

  # D-8：mynetd 非 root 运行。User= 缺失即回到 root，属回归。
  _user=$(grep '^User=' "$_u" | head -1 | cut -d= -f2)
  if [ -z "$_user" ]; then
    bad "unit 无 User=（将以 root 运行，违反 D-8）"
  elif [ "$_user" = root ]; then
    bad "unit 的 User=root（违反 D-8：mynetd 非 root）"
  else
    ok "unit 以非 root 用户运行（User=${_user}）"
  fi

  # 跨文件一致性：unit 的 ExecStart 必须指向 install-linux.sh 的默认 PREFIX。
  # 两边任一处改了路径，服务就会起不来，而这种断裂**没有任何运行期报错**。
  # shellcheck disable=SC2016  # sed 程序里的 ${PREFIX:-...} 是要匹配的字面量，故意不展开
  _prefix=$(sed -n 's/^PREFIX="${PREFIX:-\([^}]*\)}".*/\1/p' "$ROOT/scripts/install-linux.sh" | head -1)
  _exec=$(grep '^ExecStart=' "$_u" | head -1 | cut -d= -f2)
  if [ -z "$_prefix" ]; then
    skipped "无法从 install-linux.sh 解析默认 PREFIX —— 路径一致性本次未检查"
  elif [ "$_exec" = "${_prefix}/bin/mynetd" ]; then
    ok "unit 的 ExecStart 与 install-linux.sh 的 PREFIX 一致（${_exec}）"
  else
    bad "路径漂移：unit ExecStart=${_exec}，但 install-linux.sh 装到 ${_prefix}/bin/mynetd"
  fi
}

lint_launchd() {
  echo "▸ lint · launchd plist"
  _p="$ROOT/launchd/club.mynet.mynetd.plist"
  if [ ! -f "$_p" ]; then bad "缺 launchd/club.mynet.mynetd.plist"; return; fi

  if command -v plutil >/dev/null 2>&1; then
    if plutil -lint "$_p" >/dev/null 2>&1; then ok "plist 可解析（plutil -lint）"; else bad "plist 解析失败"; return; fi
    _label=$(plutil -extract Label raw -o - "$_p" 2>/dev/null)
    _prog=$(plutil -extract ProgramArguments.0 raw -o - "$_p" 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    _label=$(python3 -c "import plistlib,sys;print(plistlib.load(open(sys.argv[1],'rb')).get('Label',''))" "$_p" 2>/dev/null)
    _prog=$(python3 -c "import plistlib,sys;a=plistlib.load(open(sys.argv[1],'rb')).get('ProgramArguments') or [];print(a[0] if a else '')" "$_p" 2>/dev/null)
    [ -n "$_label" ] && ok "plist 可解析（python3 plistlib）"
  else
    skipped "plutil 与 python3 都不可用 —— plist 本次未检查"
    return
  fi

  # launchd 约定：Label 应与文件名一致，否则 load 后无法按名管理
  if [ "$_label" = club.mynet.mynetd ]; then
    ok "plist 的 Label 与文件名一致（${_label}）"
  else
    bad "plist 的 Label='${_label}'，应为 club.mynet.mynetd（与文件名一致）"
  fi
  case "$_prog" in
    /*mynetd) ok "plist 的 ProgramArguments 是绝对路径且指向 mynetd（${_prog}）" ;;
    *)        bad "plist 的 ProgramArguments 异常：'${_prog}'（应为绝对路径且以 mynetd 结尾）" ;;
  esac
  for key in RunAtLoad KeepAlive; do
    if grep -q "<key>${key}</key>" "$_p"; then ok "plist 有 ${key}"; else bad "plist 缺 ${key}（常驻进程需要它）"; fi
  done
}

# ── test ─────────────────────────────────────────────────────
# 行为测试：install-linux.sh 是否真的尊重 PREFIX/STATE（R3-5 的判据），
# 以及**缺产物时是否失败**（此前它退出码 0、什么都不装、还打印 done）。
test_install() {
  echo "▸ test · install-linux.sh 行为"
  _t=$(mktemp -d)
  _dist="$ROOT/dist/mynet_agent_linux_amd64"
  _had_dist=0
  [ -d "$ROOT/dist" ] && _had_dist=1

  cleanup() {
    rm -rf "$_t"
    if [ "$_had_dist" -eq 0 ]; then rm -rf "$ROOT/dist"; fi
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
  rm -rf "$ROOT/dist"
  _out=$(PREFIX="$_t/p3" STATE="$_t/s3" sh "$ROOT/scripts/install-linux.sh" 2>&1)
  _rc=$?
  if [ "$_rc" -ne 0 ]; then ok "缺产物时失败（退出码 ${_rc}），不再静默装空布局"
  else bad "缺产物时仍退出码 0 —— 静默空安装（V2-9 同源缺陷）"; fi
  case "$_out" in
    *找不到*) ok "缺产物时报错指明了缺哪个文件" ;;
    *)        bad "缺产物时未说明缺什么；输出：$(printf '%s' "$_out" | head -1)" ;;
  esac
  if [ ! -d "$_t/p3/bin" ] || [ -z "$(ls -A "$_t/p3/bin" 2>/dev/null)" ]; then
    ok "缺产物时没有留下半套布局"
  else
    bad "缺产物时仍写入了 PREFIX/bin"
  fi

  cleanup
  trap - EXIT INT TERM
}

# ── 调度 ─────────────────────────────────────────────────────
case "$MODE" in
  lint) lint_shell; lint_systemd; lint_launchd ;;
  test) test_install ;;
  all)  lint_shell; lint_systemd; lint_launchd; test_install ;;
  *)    echo "用法：sh scripts/check.sh [lint|test|all]"; exit 2 ;;
esac

echo
printf 'desktop 检查：%s 通过 / %s 失败 / %s 已跳过\n' "$pass" "$fail" "$skip"
if [ "$skip" -ne 0 ]; then
  echo "  ⚠ 有 ${skip} 项被跳过 —— 跳过不是通过，缺的工具装上后需重跑"
fi
[ "$fail" -eq 0 ] || { printf '失败项:%s\n' "$FAILED"; exit 1; }
exit 0
