# 安装指南 — MyNet Agent（三平台）

> 产物由 `mynet_agent` 的 `make dist` 产出，安装器由 `mynet_desktop` 打包。
> 命名 SSOT：`mynet_agent_{platform}_{arch}_{version}.{tgz|zip|exe|pkg|dmg}`。

## 已定约定（2026-09-26 确认）

| 项 | 约定 |
|---|---|
| **安装路径** | Linux/macOS `/opt/mynet` · Windows `C:\Program Files\MyNet` |
| **状态/配置** | `/opt/mynet` · Windows `%ProgramData%\MyNet` |
| **默认网关** | `wss://gw.mynet.club`（安装时可改） |
| **本机 API / 面板** | `http://127.0.0.1:8096/`（SSOT：`mynetd.DefaultLocalAPI`） |
| **命名** | `mynet_agent_{platform}_{arch}_{v*}.{tgz\|zip\|exe\|pkg\|dmg}` |
| **发行** | `ctl.mynet.club` 下载页（exe/dmg/pkg 已纳入 parseFilename） |
| **图标** | MyNet logo（`mynet_ctl/public/images/icon.png`） |

---

## 提权说明（必读）

**安装和运行都需要管理员/root**，这不是软件“要权限”，而是隧道能力属于系统层：

| 为什么 | 平台表现 |
|---|---|
| **创建 / 管理 TUN 虚拟网卡** | Linux `CAP_NET_ADMIN` / macOS `utun` / Windows `wintun` |
| **写系统路由表、防火墙规则** | `route`/`ip`、PF、`netsh` |
| **注册系统服务** | systemd / LaunchDaemon / 计划任务（SYSTEM） |
| **安装到系统目录** | `/opt/mynet`、`Program Files`、`/Library/LaunchDaemons` |

| OS | 提权时机 | 用户会看到 |
|---|---|---|
| **macOS** | 双击 .pkg 时 | 系统弹「安装器想要更改系统」→ 输密码 |
| **Windows** | 双击 .exe 时 | UAC「你要允许此应用对你的设备进行更改吗？」 |
| **Linux** | `sudo ./mynet install` | 终端要 sudo；`mynetd` 服务以 root 跑（管 TUN） |

安装器内会再提示一次原因（NSIS 有说明对话框）。桌面托盘**本身不需要 root**，
只是「启动/停止节点」时由已注册的服务（SYSTEM/root）去操作。

---

## 配置备份 / 恢复

```bash
mynet config export -o mynet-config-2026-09-26.tar.gz   # 含 conf/ + var/token，不含日志
mynet config import mynet-config-….tar.gz --dry-run     # 先看清单
mynet config import mynet-config-….tar.gz               # 导入；自动打 pre-restore-*.bak
```

托盘菜单也有「导出配置…」「导入配置…」。恢复后需重启服务。

**升级语义（8096 冲突）：**
| 端口状态 | 行为 |
|---|---|
| 空闲 | 正常安装 |
| **我们的旧版 MyNet** | 走升级：停旧服务 → 覆盖 `bin/` → **保留 `conf/` 与 `var/token`** |
| **别的进程** | **拒绝安装**，提示端口占用，不硬抢 |

---

## 总览

| 平台 | 安装包 | 怎么装 | 常驻形态 |
|---|---|---|---|
| **Linux** | `.tgz` | 解压 + `sudo ./mynet install` | systemd（`mynetd.service` + `mynet_gnb.service`） |
| **macOS** | `.dmg`（内含 `.pkg`） | 双击 pkg 向导 | launchd（`com.mynet.mynetd`） |
| **Windows** | `.exe`（NSIS） | 双击安装向导 | 计划任务 `MyNetd`（onstart + SYSTEM） |

---

## Linux（tgz）

### 装

```bash
tar -xzf mynet_agent_linux_amd64_v*.tgz
cd mynet_agent_linux_amd64_v*

# 看一遍将要做什么
sudo ./mynet install --gateways wss://gw.mynet.club --dry-run

# 真装
sudo ./mynet install --gateways wss://gw.mynet.club
```

`mynet install` 会做完整条链（`mynet/cmd_install.go`）：

1. 停已有服务（避免 `text file busy`）
2. 落二进制到 `/opt/mynet/bin/{mynet,mynetd}`
3. 建 `$MYNET_HOME/{conf,var}`
4. 写 `/etc/mynet/mynetd.env`
5. 写 systemd 单元（内嵌在二进制里）
6. `daemon-reload` + `enable --now mynetd mynet_gnb`

常用参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `--prefix DIR` | `/opt/mynet` | 二进制安装目录 |
| `--home DIR` | `/opt/mynet` | 状态目录（节点身份在这） |
| `--gateways URL[,URL]` | 必填 | 网关地址 |
| `--gnb-bin PATH` | `/usr/local/bin/gnb` | gnb 可执行文件 |
| `--no-enable` | — | 只写文件，不启动 |
| `--dry-run` | — | 只打印，不落盘 |

也可以用布局脚本（不装服务，适合容器/测试）：

```bash
PREFIX=/opt/mynet sudo sh mynet_desktop/scripts/install-linux.sh
```

### 卸载

```bash
sudo ./mynet uninstall          # 停服务、删二进制与单元
# 节点身份/密钥保留在 /opt/mynet/conf，确认不要了再删
```

### 验证

```bash
systemctl status mynetd --no-pager
journalctl -u mynetd -f
curl -sS http://127.0.0.1:8096/api/v1/wizard/state
```

---

## macOS（DMG + pkg）

### 打安装包

在 Mac 上（需要 Xcode CLT / `pkgbuild` / `hdiutil`）：

```bash
# 1) 先出 darwin 产物
cd mynet_agent && make dist && cd ..

# 2) 打 pkg
sh mynet_desktop/macos/build-pkg.sh \
  mynet_agent/dist/mynet_agent_darwin_arm64_v1.0.0 v1.0.0

# 3) 包一层 dmg
sh mynet_desktop/macos/build-dmg.sh \
  mynet_desktop/dist/mynet_agent_darwin_arm64_v1.0.0.pkg
```

### 装

1. 打开 `mynet_agent_darwin_*.dmg`
2. 双击 **MyNet Agent.pkg**，按向导走（需要管理员密码）
3. 装完 LaunchDaemon 自动拉起

安装过程（pkg 的 scripts/）：

| 时机 | 脚本 | 做什么 |
|---|---|---|
| 装之前 | `preinstall` | `launchctl bootout` 旧服务（升级时防占用/双实例） |
| 装之后 | `postinstall` | 建 `/opt/mynet`、`/var/log/mynet`，`bootstrap` launchd |

布局：

```
/Applications/MyNet.app                       # 启动台/应用程序里的托盘入口（LSUIElement，不占 Dock）
  └ Contents/MacOS/MyNet                      # 就是 mynet_tray 二进制
/Library/LaunchAgents/club.mynet.tray.plist   # 托盘登录自启（gui 域，由 mynet install 写入）
/opt/mynet/bin/{mynet,mynetd,mynet_gateway}   # WebUI 已 embed 进 mynetd，无 webui.html
/Library/LaunchDaemons/com.mynet.mynetd.plist
/opt/mynet/              节点状态与配置（卸载默认保留）
/var/log/mynet/mynetd.{log,err}
```

`MyNet.app` 是 `LSUIElement=true` 的纯菜单栏 agent，不在 Dock 占位。它归
`/Library/LaunchAgents`，**下次登录**由 launchd 自动加载。

pkg 安装期的 `postinstall` 跑在 `package_script_service` 域，`launchctl asuser`
换了 uid 也进不去 `gui/<uid>` 的 bootstrap 上下文，bootstrap 恒返回
`5: Input/output error` —— 这是平台限制，不是配置错。所以**双击 pkg 装完，
菜单栏不会立刻出现图标**：请从启动台/应用程序打开 MyNet，或重新登录一次。

`mynet install` 在 bootstrap 前会先跑 `launchctl enable gui/<uid>/club.mynet.tray`：
job 一旦被 disable 过（历史卸载、或者有测试碰过真实 launchctl），少了这步
即使从用户终端跑也照样 EIO。

### 卸载

```bash
sudo launchctl bootout system/com.mynet.mynetd
sudo rm -f /Library/LaunchDaemons/com.mynet.mynetd.plist
launchctl bootout gui/$(id -u)/club.mynet.tray
sudo rm -f /Library/LaunchAgents/club.mynet.tray.plist
sudo rm -rf /Applications/MyNet.app
sudo rm -rf /opt/mynet
# 确认不要节点身份了再：sudo rm -rf /opt/mynet
```

### 验证

```bash
sudo launchctl print system/com.mynet.mynetd | head
tail -f /var/log/mynet/mynetd.log
```

---

## Windows（NSIS .exe）

### 打安装包

```bash
# 1) 先出 windows 产物（make dist 已含 windows:amd64）
cd mynet_agent && make dist && cd ..

# 2) 编 NSIS（需要 makensis）
sh mynet_desktop/nsis/build-nsis.sh \
  mynet_agent/dist/mynet_agent_windows_amd64_v1.0.0 v1.0.0
```

`makensis` 安装：macOS `brew install makensis` · Windows 用官方安装包 · Linux `apt install nsis`。

### 装

1. 双击 `mynet_agent_windows_amd64_v*.exe`
2. 选目录（默认 `C:\Program Files\MyNet`）
3. 可选组件「配置网关地址」——或装完后编辑 `C:\Program Files\MyNet\etc\gateways.txt`
4. 完成后计划任务 `MyNetd` 已注册并启动

布局：

```
C:\Program Files\MyNet\bin\{mynet,mynetd,mynet_gateway}.exe
C:\Program Files\MyNet\bin\mynetd-start.cmd   # 环境包装 + 拉起
C:\Program Files\MyNet\etc\gateways.txt
C:\ProgramData\MyNet\{conf,var}               # MYNET_HOME（节点身份）
```

### ⚠️ 计划任务 ≠ SCM 服务

Windows 侧是 **SCM 服务 `mynetd`**（mynetd 已接 `golang.org/x/sys/windows/svc`），
登记由 `mynet install` 完成；启停统一走 CLI：

| 想做什么 | 命令（管理员） |
|---|---|
| 看状态 | `mynet service status`（或 `sc query mynetd`） |
| 启动 / 停止 / 重启 | `mynet service start \| stop \| restart` |
| 重新装配（改 env 后） | `mynet install --gateways <wss://…>` |

**已废弃**：旧版的 `service.ps1`（自建 `schtasks` 计划任务）已删除 —— 服务登记只归
`mynet install`。

### 卸载

控制面板 → 程序和功能 → **MyNet Agent** → 卸载。

卸载器会：停任务 → 删二进制与 PATH → **保留** `C:\ProgramData\MyNet`（节点身份）。

---

## 装完之后（三平台共同）

节点身份不在安装器里代劳（密钥归属节点自己）：

```bash
# 1) 生成节点身份
sudo mynet setup --vpn-type gnb --back-pub <back 公钥 hex>

# 2) 把 public_hex 用用户 token 上传到 back
#    PUT /api/v1/nodes/<id>/keys
#    {"custom_public_key":"<hex>","key_type":"gnbkey"}

# 3) 重启常驻进程，触发：拉 bundle → 渲染驱动配置 → 装路由
sudo systemctl restart mynetd          # Linux
sudo launchctl kickstart -k system/com.mynet.mynetd   # macOS
# Windows：mynet service restart
```

---

## 构建入口（mynet_desktop/Makefile）

```bash
cd mynet_desktop
make pack-linux   # 校验 tgz 布局（真包在 mynet_agent 的 make dist）
make pack-pkg     # macOS .pkg
make pack-dmg     # macOS .dmg（需在 Mac 上）
make pack-nsis    # Windows .exe
make pack-all     # 能打的全打
```

---

## GitHub Actions 自动发版

工作流：`.github/workflows/release.yml`

| 触发 | 行为 |
|---|---|
| push tag `v*` | 全量构建 + 打包 + 挂 GitHub Release |
| `workflow_dispatch` | 手工出包（可传 `agent_ref` / `version`） |

流水线分工：

```text
version ─┬─ build-binaries (ubuntu, mynet_agent make dist)
         ├─ package-linux  (ubuntu, 校验 tgz)
         ├─ package-windows(ubuntu, makensis → NSIS .exe)
         ├─ package-macos  (macos-14, pkgbuild + hdiutil)
         └─ publish        (仅 tag → GitHub Release)
```

跨仓约定：

- 二进制来自 `mynet-club/mynet_agent-V2`，安装器脚本在本仓
- tag 发版优先用 **同名 agent tag**；agent 没打这个 tag 就退回默认分支
- 产物命名与本地一致：`mynet_agent_{platform}_{arch}_{version}.{tgz|exe|pkg|dmg}`

本地等价命令：

```bash
cd mynet_agent && make dist VERSION=v1.0.0
cd ../mynet_desktop
make pack-pkg pack-dmg pack-nsis AGENT_DIST=../mynet_agent/dist VERSION=v1.0.0
```

---

## 配置树（v2）与 proxy 插件

```text
$MYNET_HOME/
  mode.json                 local | online/{tenant}/{node}
  conf/local|online/…       intent / profile / keys / plugins
  driver/gnb/conf/<id>/     Apply 投影 + proxy.conf
  plugins/  var/  state/
```

```bash
mynet setup --local --node-id …     # 或 --online --tenant …
mynet apply --active
mynet plugin install proxy
mynet plugin exits add <peer> --weight 20 --order 1
mynet plugin enable proxy           # 总开关（默认关）
```

启用后 apply 会：探测 gnb `Features: proxy`（P2 补丁 0005）→ 写
`proxy.conf` + 出口 f 角色 + `proxy on`；不支持则明确提醒、不写半截配置。

---

## 桌面托盘（mynet_tray）

Windows / macOS 菜单栏/系统托盘，装完在 `bin/mynet_tray`（Windows 另有开始菜单项）。

| 菜单 | 行为 |
|---|---|
| 状态：… | 状态机一言之（已停止 / 启动中 / 运行中 / 降级运行 / 异常 / 停止中） |
| 启动 / 停止节点 | 按状态机禁用；走 launchd（mac）或计划任务 `MyNetd`（win） |
| 进入面板 | 打开 `http://127.0.0.1:8096/` |
| 开机启动 | macOS LaunchAgent `club.mynet.tray` / Windows 注册表 Run |
| 退出 | 只退托盘，**不停**节点 |

状态机（`mynet_agent/cmd/mynet_tray/fsm.go`）：

```text
            ┌──────────────────────────────────────┐
            │                                      │
            ▼                                      │
        ┌────────┐  Start   ┌─────────┐  DaemonUp  │
        │Stopped │─────────►│Starting │───────────►│
        └────────┘          └─────────┘            │
            ▲                  │ StartTimeout       │
            │                  ▼                    │
            │              ┌───────┐               │
            │              │Failed │◄── NodeFailed ─┤
            │              └───────┘               │
            │                  │ Start (retry)     │
            │                  ▼                   │
        DaemonDown        ┌─────────┐              │
            │             │Starting │              │
            │             └─────────┘              │
            │                                      │
            │         ┌─────────┐  NodeDegraded  ┌─────────┐
            └─────────┤ Running │◄──────────────►│Degraded │
                      └─────────┘   NodeHealthy  └─────────┘
                            │                          │
                            │ Stop                     │ Stop
                            ▼                          ▼
                      ┌──────────┐              ┌──────────┐
                      │ Stopping │─────────────►│ Stopping │
                      └──────────┘  DaemonDown  └──────────┘
```

探针每 3s 打一次 `GET /api/v1/node-status`（mynetd 活着时），映射为
`RUNNING/DEGRADED/FAILED`；API 无响应 = Stopped。**判定只在 fsm.go**，
UI 不自己拼状态。

---

## 待办（别当已完成）

| 项 | 说明 |
|---|---|
| **Windows 真服务** | mynetd 接 `windows/svc` 后，NSIS 改 `sc create` + `sc start` |
| **代码签名** | macOS pkg/dmg 与 Windows exe 都未签名，首次打开会被 Gatekeeper / SmartScreen 拦 |
| **ctl 上传** | `parseFilename` 目前只认 `tgz\|zip\|tar.gz\|ipk`，exe/pkg/dmg 走官网下载页，不进 ctl 发版 API |
| **Release 后自动传 ctl** | 需要 `CTL_UPLOAD_TOKEN` secret；脚本在 `mynet_agent/scripts/release/upload-to-ctl.sh` |
