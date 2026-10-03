# service.ps1 — Windows 上的 mynetd 常驻管理（E-7）
#
# 为什么是计划任务而不是 SCM 服务：
#   mynetd 目前没有接 golang.org/x/sys/windows/svc，sc create 能注册
#   但 sc start 会 1053（服务未及时响应）。计划任务（onstart + SYSTEM）
#   是不用改 Go 代码就能用的常驻形态。等 mynetd 接了 svc 再换成真服务。
#
# 用法（管理员 PowerShell）：
#   .\service.ps1 start|stop|restart|status
#   .\service.ps1 install [-Gateways wss://…] [-Prefix 'C:\Program Files\MyNet']
#   .\service.ps1 uninstall [-KeepData]
param(
  [Parameter(Position = 0)]
  [ValidateSet('install', 'uninstall', 'start', 'stop', 'restart', 'status')]
  [string]$Action = 'status',

  [string]$Gateways = '',
  [string]$Prefix = "$env:ProgramFiles\MyNet",
  [string]$Home = "$env:ProgramData\MyNet",
  [switch]$KeepData
)

$ErrorActionPreference = 'Stop'
$TaskName = 'MyNetd'
$Bin = Join-Path $Prefix 'bin'
$StartCmd = Join-Path $Bin 'mynetd-start.cmd'

# 本机 API/WebUI 端口，SSOT = mynet_agent/mynet/port_owner.go 的 DefaultLocalAPI。
# 必须与 mynet-agent.nsi 的 ${LOCAL_API}（面板快捷方式指向它）一致，否则装完点开是空页面
# （8711 是 mynet_gateway 的历史端口，181 节点真机踩过）。
$ListenAddr = '127.0.0.1:8096'

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '需要管理员权限。请用「以管理员身份运行」打开 PowerShell。'
  }
}

function Write-StartCmd {
  $gwLine = ''
  if ($Gateways) {
    $gwLine = "set MYNET_GATEWAYS=$Gateways`r`n"
  }
  $body = @"
@echo off
set MYNET_HOME=$Home
set MYNET_BIN=$Bin\mynet.exe
set PATH=$Bin;%PATH%
$gwLine"$Bin\mynetd.exe" -listen $ListenAddr
"@
  New-Item -ItemType Directory -Force -Path (Split-Path $StartCmd) | Out-Null
  Set-Content -Path $StartCmd -Value $body -Encoding ASCII
  Write-Host "installed $StartCmd"
}

function Install-Task {
  if (-not (Test-Path $StartCmd)) { Write-StartCmd }
  # /RU SYSTEM：节点模式要建 tun / 写路由
  schtasks /create /tn $TaskName /tr "`"$StartCmd`"" /sc onstart /ru SYSTEM /rl HIGHEST /f | Out-Host
  Write-Host "task installed: $TaskName"
}

# 只认「可执行文件在本次安装目录下」的进程。红线禁止按名字杀（AGENTS.md「禁止按名字杀
# 进程」）：同名 mynetd 可能并存（开发机手跑的一个、另一份安装的一个），按名字停会误伤。
# schtasks /end 才是首选停法，这里只是它没收干净时的兜底，故按路径精确匹配。
function Get-OwnProcess {
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($Bin, [StringComparison]::OrdinalIgnoreCase) }
}

function Stop-OwnProcess {
  Get-OwnProcess | ForEach-Object {
    Write-Host "stopping $($_.Name) pid=$($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
}

function Uninstall-Task {
  schtasks /end /tn $TaskName 2>$null | Out-Null
  schtasks /delete /tn $TaskName /f 2>$null | Out-Null
  Stop-OwnProcess
  Write-Host "task removed: $TaskName"
}

switch ($Action) {
  'install' {
    Assert-Admin
    New-Item -ItemType Directory -Force -Path (Join-Path $Home 'conf'), (Join-Path $Home 'var') | Out-Null
    Write-StartCmd
    Install-Task
    schtasks /run /tn $TaskName | Out-Host
    Write-Host "done: prefix=$Prefix home=$Home"
  }
  'uninstall' {
    Assert-Admin
    Uninstall-Task
    if (-not $KeepData -and (Test-Path $Home)) {
      Remove-Item -Recurse -Force $Home
      Write-Host "removed $Home"
    } else {
      Write-Host "kept $Home（节点身份/密钥）"
    }
  }
  'start'   { Assert-Admin; schtasks /run /tn $TaskName | Out-Host }
  'stop'    { Assert-Admin; schtasks /end /tn $TaskName | Out-Host; Stop-OwnProcess }
  'restart' { Assert-Admin; & $PSCommandPath stop; & $PSCommandPath start }
  'status'  {
    schtasks /query /tn $TaskName /fo LIST 2>$null | Out-Host
    Get-OwnProcess |
      Select-Object Name, ProcessId, ExecutablePath | Format-Table -AutoSize | Out-Host
  }
}
