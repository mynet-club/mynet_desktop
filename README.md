# mynet_desktop-V2

MyNet 非 OpenWrt 平台适配层：安装 · 系统服务 · 打包。

与 **`mynet_openwrt`** 对等，一平台一份。

| 做 | 不做 |
|---|---|
| systemd / launchd / Windows 服务 | 业务逻辑（归 mynetd / mynet） |
| 二进制布局与 PATH、conf 模板、logrotate | WebUI 业务（归 mynet_web） |
| 打包（deb / rpm / pkg / tgz / zip） | 长期保留 Node 客户端 |

产物命名：**`mynet_agent_*`**（不是 `agent_*`）。

## 文档

`mynet_ctl/docs/knowledge-base/repo-migration.md`（§2 各项目决策）· `dev-plan.md`
