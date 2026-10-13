; mynet-agent.nsi — Windows 安装向导（E-7）
;
; 产物命名对齐 AGENTS.md §1.5：mynet_agent_{platform}_{arch}_{version}.exe
; 用法（由 scripts/build-nsis.sh 调用，也可手工）：
;   makensis -DVERSION=v1.0.0 -DARCH=amd64 -DSRCDIR=... -DOUTFILE=... mynet-agent.nsi
;
; 安装过程：
;   1. 选目录（默认 C:\Program Files\MyNet）
;   2. 落盘 mynet / mynetd / mynet_tray（WebUI 已 embed 进 mynetd，无 webui.html）
;   3. **服务装配委托 `mynet install`**（SEC_START）：它写 $ProgramData\MyNet\mynetd.env、
;      `sc create mynetd` + start、注册托盘自启、并拉起 WebUI —— 安装器只落文件。
;   4. 加 PATH、写卸载项
;
; ⚠️ 本向导**不自建登记**：旧版用 `schtasks` 计划任务（当时 mynetd 无 SCM 句柄），
;    现 mynetd 已接 golang.org/x/sys/windows/svc，登记统一归 `mynet install`，
;    即合同「系统登记只有一个 owner」。旧计划任务在 `mynet install` 里会被清掉。

!ifndef VERSION
  !define VERSION "v0.0.0-dev"
!endif
!ifndef ARCH
  !define ARCH "amd64"
!endif
; 驱动依赖二进制（随包分发）：仓内 nsis/vendor/wintun/wintun.dll（provenance/SHA 见
; nsis/wintun-provenance.md）。build-nsis.sh 会校验 SHA 并 -D 传入。
!ifndef WINTUN_DLL
  !define WINTUN_DLL "${__FILEDIR__}\vendor\wintun\wintun.dll"
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
; SCM 服务名（由 `mynet install` 注册/管理；sc query mynetd 可见）
!define SVC_NAME        "mynetd"
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
1. 注册系统服务 mynetd（SCM，SYSTEM 账户）$\r$\n\
2. 创建/管理 TUN 虚拟网卡$\r$\n\
3. 写入系统路由表与防火墙规则$\r$\n\
4. 安装到 Program Files$\r$\n$\r$\n\
节点数据保存在 ProgramData\MyNet，卸载时默认保留。"

  SetOutPath "$INSTDIR\bin"
  File "${SRCDIR}\mynet.exe"
  File "${SRCDIR}\mynetd.exe"
  ; ⚠️ 客户端包**不含** mynet_gateway —— 它是**服务端**组件（见 mynet_agent/scripts/pack.sh）。
  ; 此前这里无条件 File mynet_gateway.exe，而 `make dist` 从不产出它 → makensis 编译即失败
  ; （2026-10-11 首次发布实测）。
  File /nonfatal "${SRCDIR}\mynet_tray.exe"

  ; 驱动依赖（A 层文件交付）：wintun.dll 必须与 gnb.exe **同目录** —— gnb 用
  ; LoadLibraryExW(..., LOAD_LIBRARY_SEARCH_APPLICATION_DIR)。实测 gnb.exe 在
  ; $INSTDIR\driver\gnb\bin，故 DLL 落同处。
  ; 无 /nonfatal：缺 DLL 时 makensis **编译即失败** —— 不产出装上去必崩的包。
  ; 来源/SHA 见 nsis/wintun-provenance.md；取件用 scripts/fetch-wintun.sh。
  SetOutPath "$INSTDIR\driver\gnb\bin"
  File "${WINTUN_DLL}"

  ; MYNET_HOME 默认放 ProgramData（可写，服务/用户都能落状态）
  CreateDirectory "$APPDATA\MyNet\conf"
  CreateDirectory "$APPDATA\MyNet\var"
  CreateDirectory "$INSTDIR\etc"

  ; 启动包装与服务登记**都不在本节**：SCM 服务由 `mynet install` 注册（见 SEC_START）。
  ; 旧版曾写 mynetd-start.cmd + `schtasks` 计划任务（自建登记），已撤。
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
    MessageBox MB_ICONINFORMATION "默认网关已写入 wss://gw.mynet.club。$\r$\n如需修改请编辑 $\r$\n$INSTDIR\etc\gateways.txt$\r$\n然后以管理员执行：mynet install --gateways <新网关>$\r$\n（service.ps1 已废弃；服务启停用 `mynet service start|stop|status`）"
  !endif
SectionEnd

Section "立即启动" SEC_START
  ; 服务装配**全部委托 `mynet install`**：写 env、sc create mynetd + start、
  ; 托盘登录自启、拉起 WebUI。安装器只落文件 —— 合同「系统登记只有一个 owner」的落点。
  SetShellVarContext all
  StrCpy $1 "wss://gw.mynet.club/v1/node/connect"
  !ifdef GATEWAYS
    StrCpy $1 "${GATEWAYS}"
  !else
    IfFileExists "$INSTDIR\etc\gateways.txt" 0 gw_default
      FileOpen $2 "$INSTDIR\etc\gateways.txt" r
      FileRead $2 $1
      FileClose $2
    gw_default:
  !endif
  nsExec::ExecToLog '"$INSTDIR\bin\mynet.exe" install --gateways "$1" --prefix "$INSTDIR" --home "$APPDATA\MyNet"'
  Pop $0
SectionEnd

; ── 卸载 ──────────────────────────────────────────────────────
Section "Uninstall"
  SetShellVarContext all
  ; 停服务/清登记委托 `mynet uninstall`（sc stop/delete mynetd + 删托盘自启键 + 删 env）；
  ; --keep-bin：二进制在 $INSTDIR\bin 由本卸载器删，不劳 CLI 去 $home\bin 找。
  ; 下面那条 PowerShell 只兜「服务已停但进程还占着文件」的残余，且**按可执行路径过滤**
  ; —— 不用 taskkill /im（红线：禁止按名字杀进程，同名 mynetd 可能来自别的实例）。
  nsExec::ExecToLog '"$INSTDIR\bin\mynet.exe" uninstall --home "$APPDATA\MyNet" --keep-bin'
  Pop $0
  nsExec::ExecToLog 'powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $$.ExecutablePath -like $\'$INSTDIR\bin\*$\' } | ForEach-Object { Stop-Process -Id $$.ProcessId -Force }"'

  Delete "$INSTDIR\bin\mynet.exe"
  Delete "$INSTDIR\bin\mynetd.exe"
  Delete "$INSTDIR\bin\mynet_tray.exe"
  Delete "$INSTDIR\bin\webui.html"   ; 旧版落盘件，卸载清遗留（G1-c 后产物不再带）
  Delete "$INSTDIR\driver\gnb\bin\wintun.dll"
  RMDir  "$INSTDIR\driver\gnb\bin"
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
