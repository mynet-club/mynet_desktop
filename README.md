# mynet_desktop-V2

MyNet 非 OpenWrt 平台适配层：安装 · 系统服务 · 打包。

与 **`mynet_openwrt`** 对等，一平台一份。

| 做 | 不做 |
|---|---|
| systemd / launchd / Windows 计划任务 | 业务逻辑（归 mynetd / mynet） |
| 二进制布局与 PATH、conf 模板、logrotate | WebUI 业务（归 mynet_web） |
| 安装器：tgz 布局 / macOS .pkg+.dmg / Windows NSIS .exe | 长期保留 Node 客户端 |

产物命名：**`mynet_agent_*`**（不是 `agent_*`）。

## 三平台安装器

| 平台 | 产物 | 入口 |
|---|---|---|
| Linux | `.tgz`（`mynet_agent make dist`） | 解压 + `sudo ./mynet install` |
| macOS | `.dmg` → `.pkg` | `make pack-dmg` |
| Windows | `.exe`（NSIS） | `make pack-nsis` |

完整安装/卸载/排障见 **[docs/INSTALL.md](docs/INSTALL.md)**。

```bash
# 前置：先出二进制
cd ../mynet_agent && make dist

# 再打安装器
cd ../mynet_desktop
make pack-linux   # 校验 tgz
make pack-pkg     # macOS .pkg
make pack-dmg     # macOS .dmg
make pack-nsis    # Windows .exe
```

**CI 自动发版**：push tag `v*` 或手动跑 `Release Installers` workflow
（`.github/workflows/release.yml`）—— 编二进制 → 打三平台安装器 → GitHub Release。

## 目录

```
systemd/          Linux 单元（mynetd.service）
launchd/          macOS LaunchDaemon（club.mynet.mynetd.plist）
nsis/             Windows 安装向导（mynet-agent.nsi + service.ps1）
macos/            pkg/dmg 构建脚本 + postinstall
scripts/          install-linux.sh · check.sh
docs/INSTALL.md   安装指南（三平台）
.github/workflows/  CI 门禁 + 发版流水线
```

## 开发

```bash
make check          # guard + lint + test
make install-hooks
```

## 文档

`mynet_ctl/docs/knowledge-base/repo-migration.md`（§2 各项目决策）· `dev-plan.md`（E-7）
