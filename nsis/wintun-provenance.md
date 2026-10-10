# Wintun DLL 来源与许可（Windows 安装器内置）

> 2026-10-10。合同 [lifecycle-contract.md](../../../mynet_ctl/docs/knowledge-base/spec/lifecycle-contract.md) §4.1A：
> 依赖交付归安装器；§4.3：安装器/驱动组件须「固定 SHA、版本/通道、签名/sha256 与来源 manifest」。

| 项 | 值 |
|---|---|
| 文件 | `wintun.dll`（**amd64**） |
| 形态 | `PE32+ DLL x86-64` · 427552 bytes |
| **SHA256** | `e5da8447dc2c320edc0fc52fa01885c103de8c118481f683643cacc3220dafce` |
| 来源 | 官方 **WireGuard LLC** Wintun 发行件；本副本取自局域网测试机 `192.168.0.5` 已部署位 `C:\Program Files\MyNet\driver\gnb\bin\wintun.dll`（与 gnb.exe 同目录，实测可用） |
| 签名 | Authenticode **Valid**；Signer `CN=WireGuard LLC, O=WireGuard LLC`（DigiCert EV Code Signing CA）；thumbprint `DF98E075A012ED8C86FBCF14854B8F9555CB3D45`。证书有效期 2018-10-12 → **2021-12-14（已过期）**，但签名含时间戳，Windows 判定 Valid |
| 许可 | 随上游（WireGuard LLC）原样分发，**仅作驱动组件、不修改** |

## 入库形态：**资源文件随包分发**

DLL **入库**在 `nsis/vendor/wintun/wintun.dll`（安装器的资源文件），由 NSIS payload 打进 `.exe`，
用户安装即得 —— 不需要联网取件、不走 ctl 直链。

因 `guard` C4 把 `*.dll` 视为「产物后缀」，本仓用**持久白名单** [`../.guard-c4-allow`](../.guard-c4-allow)
放行该路径（环境变量 `C4_ALLOW` 只在当次提交有效，不能替代）。

**换文件**必须同步三处：本文件的 SHA256、`nsis/build-nsis.sh` 的固定 `WINTUN_SHA256`、白名单路径。
`build-nsis.sh` 每次出包都会校验 SHA，不匹配直接失败。

## 落位（必须与 gnb.exe 同目录）

gnb 用 `LoadLibraryExW(L"wintun.dll", NULL, LOAD_LIBRARY_SEARCH_APPLICATION_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32)`
找 DLL —— `APPLICATION_DIR` 即 **gnb.exe 所在目录**。实测 gnb.exe 在 `$INSTDIR\driver\gnb\bin`，
故安装器把 DLL 落到**同一处**。

> NSIS 的 `File` **不带 `/nonfatal`** —— 仓里缺 DLL 时 makensis **编译即失败**，不产出"装上去必崩"的包。
> gnb 侧 `init_tun_wintun` 的 NULL 分支**不改**（用户裁定 2026-10-10）：由本层保证 DLL 在场。
