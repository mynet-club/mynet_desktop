; mynet-agent.nsi — Windows 安装向导（E-7）
;
; 产物命名对齐 AGENTS.md §1.5：mynet_agent_{platform}_{arch}_{version}.exe
; 用法（由 scripts/build-nsis.sh 调用，也可手工）：
;   makensis -DVERSION=v1.0.0 -DARCH=amd64 -DSRCDIR=... -DOUTFILE=... mynet-agent.nsi
;
; 安装过程：
;   1. 选目录（默认 C:\Program Files\MyNet）
;   2. 落盘 mynet / mynetd / mynet_gateway / webui.html
;   3. 写 MYNET_HOME / MYNET_GATEWAYS 机器环境变量
;   4. 用「计划任务」注册开机自启 —— mynetd 目前**不是** Windows 服务
;      （无 SCM 句柄，sc create 会 1053），计划任务是能用的常驻形态。
;   5. 加 PATH、写卸载项
;
; ⚠️ 计划任务 ≠ SCM 服务：sc stop / services.msc 管不了它，
;    停止请用 scripts\service.ps1 stop 或卸载器。等 mynetd 接了
;    golang.org/x/sys/windows/svc 之后再换成真服务。

!ifndef VERSION
  !define VERSION "v0.0.0-dev"
!endif
!ifndef ARCH
  !define ARCH "amd64"
!endif
!ifndef SRCDIR
  !error "SRCDIR 未定义：请传入包含 mynet.exe/mynetd.exe 的目录"
!endif
!ifndef OUTFILE
  !define OUTFILE "mynet_agent_windows_${ARCH}_${VERSION}.exe"
!endif

!define PRODUCT_NAME    "MyNet Agent"
!define PRODUCT_PUBLISHER "MyNet Club"
!define PRODUCT_DIR     "MyNet"
!define SERVICE_TASK    "MyNetd"
!define UNINST_KEY      "Software\Microsoft\Windows\CurrentVersion\Uninstall\MyNetAgent"

; 本机 API/WebUI 地址，SSOT = mynet_agent/mynet/port_owner.go 的 DefaultLocalAPI。
; mynetd 的 -listen 与「MyNet 面板」快捷方式必须同源，否则装完点开是空页面
; （8711 是 mynet_gateway 的历史端口，181 节点真机踩过）。改端口只改这一处。
!define LOCAL_API       "127.0.0.1:8096"

Unicode true
; 必须管理员：写 Program Files、注册计划任务（SYSTEM）、建 TUN 要提权。
; 详见 docs/INSTALL.md「提权说明」。
RequestExecutionLevel admin

Name "${PRODUCT_NAME} ${VERSION}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\${PRODUCT_DIR}"
InstallDirRegKey HKLM "Software\MyNet" "InstallDir"
BrandingText "${PRODUCT_NAME} ${VERSION}"
Icon "app.ico"
UninstallIcon "app.ico"

Page directory
Page components
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

; ── 组件 ──────────────────────────────────────────────────────
Section "核心组件（必选）" SEC_CORE
  SectionIn RO

  ; ProgramData：NSIS 没有 $COMMONAPPDATA 常量。
  ; SetShellVarContext all 之后 $APPDATA = C:\ProgramData（机器级）。
  SetShellVarContext all

  MessageBox MB_ICONINFORMATION \
    "MyNet 需要管理员权限，原因：$\r$\n$\r$\n\
1. 服务注册到系统（计划任务，SYSTEM 账户）$\r$\n\
2. 创建/管理 TUN 虚拟网卡$\r$\n\
3. 写入系统路由表与防火墙规则$\r$\n\
4. 安装到 Program Files$\r$\n$\r$\n\
节点数据保存在 ProgramData\MyNet，卸载时默认保留。"

  SetOutPath "$INSTDIR\bin"
  File "${SRCDIR}\mynet.exe"
  File "${SRCDIR}\mynetd.exe"
  File "${SRCDIR}\mynet_gateway.exe"
  File /nonfatal "${SRCDIR}\mynet_tray.exe"
  File /nonfatal "${SRCDIR}\webui.html"

  ; MYNET_HOME 默认放 ProgramData（可写，服务/用户都能落状态）
  CreateDirectory "$APPDATA\MyNet\conf"
  CreateDirectory "$APPDATA\MyNet\var"
  CreateDirectory "$INSTDIR\etc"

  ; 启动包装：先设环境再拉起 mynetd。计划任务跑的是这个，
  ; 免得去改机器级环境变量后还要重登录才生效。
  FileOpen $0 "$INSTDIR\bin\mynetd-start.cmd" w
  FileWrite $0 "@echo off$\r$\n"
  FileWrite $0 "set MYNET_HOME=$APPDATA\MyNet$\r$\n"
  FileWrite $0 "set MYNET_BIN=$INSTDIR\bin\mynet.exe$\r$\n"
  FileWrite $0 "set PATH=$INSTDIR\bin;%PATH%$\r$\n"
  ; MYNET_GATEWAYS 由安装向导的「网关」组件写入；未选时留空（console 模式）
  IfFileExists "$INSTDIR\etc\gateways.txt" 0 gw_done
    FileOpen $1 "$INSTDIR\etc\gateways.txt" r
    FileRead $1 $2
    FileClose $1
    FileWrite $0 "set MYNET_GATEWAYS=$2$\r$\n"
  gw_done:
  FileWrite $0 '"$INSTDIR\bin\mynetd.exe" -listen ${LOCAL_API}$\r$\n'
  FileClose $0

  ; 计划任务：开机自启 + 崩溃拉起（/RI 间隔 restart）
  ; /RU SYSTEM：节点模式要建 tun / 写路由，普通用户起不来
  nsExec::ExecToLog 'schtasks /create /tn "${SERVICE_TASK}" /tr "$INSTDIR\bin\mynetd-start.cmd" /sc onstart /ru SYSTEM /rl HIGHEST /f'
  Pop $0

  ; 卸载注册表
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName"     "${PRODUCT_NAME}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion"  "${VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher"       "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon"     "$INSTDIR\bin\mynet.exe"
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1
  WriteRegStr HKLM "Software\MyNet" "InstallDir" "$INSTDIR"

  ; PATH（机器级，用户新开的终端才看得到）。不依赖 EnVar 插件：
  ; 直接读写 HKLM\...\Session Manager\Environment\Path，makensis 开箱能用。
  Call AddToPath

  ; 开始菜单：面板 + 托盘
  CreateDirectory "$SMPROGRAMS\MyNet"
  CreateShortCut "$SMPROGRAMS\MyNet\MyNet 面板.lnk" "http://${LOCAL_API}/"
  IfFileExists "$INSTDIR\bin\mynet_tray.exe" 0 +2
    CreateShortCut "$SMPROGRAMS\MyNet\MyNet 托盘.lnk" "$INSTDIR\bin\mynet_tray.exe"
SectionEnd

Section /o "配置网关地址" SEC_GW
  ; 默认网关 gw.mynet.club（约定 2026-09-26）。静默安装用 /GATEWAYS=… 覆盖。
  !ifdef GATEWAYS
    FileOpen $0 "$INSTDIR\etc\gateways.txt" w
    FileWrite $0 "${GATEWAYS}"
    FileClose $0
  !else
    FileOpen $0 "$INSTDIR\etc\gateways.txt" w
    FileWrite $0 "wss://gw.mynet.club"
    FileClose $0
    MessageBox MB_ICONINFORMATION "默认网关已写入 wss://gw.mynet.club。$\r$\n如需修改请编辑 $\r$\n$INSTDIR\etc\gateways.txt$\r$\n然后以管理员重启计划任务 ${SERVICE_TASK}$\r$\n（service.ps1 不随安装包落盘，见 docs/INSTALL.md）"
  !endif
SectionEnd

Section "立即启动" SEC_START
  nsExec::ExecToLog 'schtasks /run /tn "${SERVICE_TASK}"'
  Pop $0
SectionEnd

; ── 卸载 ──────────────────────────────────────────────────────
Section "Uninstall"
  SetShellVarContext all
  ; 先停任务再删文件，否则 mynetd 占用导致删不掉。
  ; schtasks /end 是首选（init 系统，精确）；下面那条 PowerShell 只兜「任务已停但
  ; 进程还占着文件」的残余，且**按可执行路径过滤**——不用 taskkill /im（红线：禁止
  ; 按名字杀进程，同名 mynetd 可能来自别的安装实例或开发机手跑）。
  nsExec::ExecToLog 'schtasks /end /tn "${SERVICE_TASK}"'
  nsExec::ExecToLog 'schtasks /delete /tn "${SERVICE_TASK}" /f'
  nsExec::ExecToLog 'powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $$.ExecutablePath -like $\'$INSTDIR\bin\*$\' } | ForEach-Object { Stop-Process -Id $$.ProcessId -Force }"'

  Delete "$INSTDIR\bin\mynet.exe"
  Delete "$INSTDIR\bin\mynetd.exe"
  Delete "$INSTDIR\bin\mynet_gateway.exe"
  Delete "$INSTDIR\bin\mynet_tray.exe"
  Delete "$INSTDIR\bin\webui.html"
  Delete "$INSTDIR\bin\mynetd-start.cmd"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir  "$INSTDIR\bin"
  RMDir  "$INSTDIR\etc"
  RMDir  "$INSTDIR"
  Delete "$SMPROGRAMS\MyNet\MyNet 面板.lnk"
  Delete "$SMPROGRAMS\MyNet\MyNet 托盘.lnk"
  RMDir  "$SMPROGRAMS\MyNet"

  ; 状态目录**故意不删**——节点身份与密钥在 ProgramData\MyNet，
  ; 误删等于丢节点身份。要清干净请手工删该目录。
  DeleteRegKey HKLM "${UNINST_KEY}"
  DeleteRegKey HKLM "Software\MyNet"

  Call un.RemoveFromPath

  MessageBox MB_ICONINFORMATION "已卸载。$\r$\n节点数据保留在 $APPDATA\MyNet（如需彻底清除请手工删除）。"
SectionEnd

; ── PATH 增删 ────────────────────────────────────────────────
; 为什么写临时 .ps1 再跑：nsExec 的命令行里 PowerShell 的 $ 会被
; NSIS 当变量吃掉（实测 19 条 warning，PATH 改了个寂寞）。
; 落盘后再执行，$ 一律安全。不用 setx：它有 1024 上限会截断 PATH。

Function AddToPath
  FileOpen $0 "$TEMP\mynet-path-add.ps1" w
  ; $$ → 字面 $（给 PowerShell）；$INSTDIR / $\r$\n 仍由 NSIS 展开
  FileWrite $0 '$$b = "$INSTDIR\bin"$\r$\n'
  FileWrite $0 '$$p = [Environment]::GetEnvironmentVariable("Path","Machine")$\r$\n'
  FileWrite $0 'if (($$p -split ";") -notcontains $$b) {$\r$\n'
  FileWrite $0 '  $$n = if ($$p) { "$$p;$$b" } else { $$b }$\r$\n'
  FileWrite $0 '  [Environment]::SetEnvironmentVariable("Path", $$n, "Machine")$\r$\n'
  FileWrite $0 '}$\r$\n'
  FileClose $0
  nsExec::ExecToLog 'powershell -NoProfile -ExecutionPolicy Bypass -File "$TEMP\mynet-path-add.ps1"'
  Pop $0
  Delete "$TEMP\mynet-path-add.ps1"
FunctionEnd

Function un.RemoveFromPath
  FileOpen $0 "$TEMP\mynet-path-del.ps1" w
  FileWrite $0 '$$b = "$INSTDIR\bin"$\r$\n'
  FileWrite $0 '$$p = [Environment]::GetEnvironmentVariable("Path","Machine")$\r$\n'
  FileWrite $0 '$$n = (($$p -split ";") | Where-Object { $$_ -ne $$b }) -join ";"$\r$\n'
  FileWrite $0 '[Environment]::SetEnvironmentVariable("Path", $$n, "Machine")$\r$\n'
  FileClose $0
  nsExec::ExecToLog 'powershell -NoProfile -ExecutionPolicy Bypass -File "$TEMP\mynet-path-del.ps1"'
  Pop $0
  Delete "$TEMP\mynet-path-del.ps1"
FunctionEnd
