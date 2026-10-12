# 开发日志 — Redmi K40S (munch) 自定义内核 / Droidspaces 适配

## 背景

目标：为红米 K40S（munch，SM8250，出厂内核 4.19）编译自定义内核，满足 [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS)（安卓上的 LXC 类容器运行时）的全部内核要求，同时保持 Magisk root 与 WiFi/传感器等硬件功能。

开发环境：Ubuntu x86_64，本地编译，全程使用 AI 辅助工具（MiMoCode / Claude）。

---

## 阶段一：需求分析与源码选型

### Droidspaces 内核要求
- Non-GKI 4.19 走「配置 fragment」路线，无需 kABI 补丁
- 必需：`SYSVIPC` / `PID_NS` / `IPC_NS` / `USER_NS` / `DEVTMPFS` / `CGROUP_DEVICE` 等
- 可选：`CFS_BANDWIDTH`（--cpus）、`CGROUP_PIDS`（--pids-limit）、`OVERLAY_FS`、NAT 网络栈

### 源码选型
| 源 | 结论 |
|---|---|
| MiCode `munch-s-oss` | ❌ `techpack/` 为空（显示驱动缺失），`dsi_display_mi.c` 缺失，链接失败 |
| **Flicker `kernel_xiaomi_sm8250`** | ✅ techpack 完整，自带 `droidspaces.config`/`ksu.config`，含 `dsi_display_mi.c` |

**教训**：小米 MiCode 开源树常年缺 techpack 私有代码，直接编译会在 vmlinux 链接时挂掉。社区维护的完整树是更可靠的选择。

---

## 阶段二：编译环境

- 工具链：AOSP **clang-r399163b**（树内 `build.config.common` 指定）+ Arm GNU binutils
- LTO：Full LTO 内存峰值 28GB+，32GB 机器 OOM → 改用 `LTO_NONE`
- `gcc-wrapper.py`（python2）与 `LLVM=1` 冲突 → `CC=clang` 绕过
- 缺 `mkdtboimg.py` → 从 LineageOS `system_libufdt` 补齐

**教训**：MiCode/Flicker 树的 `gcc-wrapper.py` 在 LLVM 模式下会因 `REAL_CC` 未定义而失败。

---

## 阶段三：首轮编译与刷机

### 配置差异审计
对比 `munch_user_defconfig` 与 Droidspaces 要求，发现致命缺口：
- `PID_NS` 被显式 `# CONFIG_PID_NS is not set`（高通安卓内核惯例）
- `SYSVIPC` / `POSIX_MQUEUE` / `DEVTMPFS` / `CGROUP_DEVICE` 无 Kconfig default

### 刷机结果（build #4，WiFi 内建）
- ✅ 开机正常，Droidspaces 配置生效
- ❌ WiFi 打不开
- ❌ 传感器异常
- ⚠️ 「设备内部出现了问题」告警

---

## 阶段四：WiFi 修复（多轮）

### 尝试 1：WiFi 模块化（build #5）
- `QCA_CLD_WLAN=m` + 音频全改模块 → **设备无法开机**
- **根因**：内建 CNSS2 + 模块化 wlan 组合不稳定；音频栈被误改
- **恢复**：fastboot 刷回原厂 boot

### 尝试 2：仅 WiFi 模块化（build #7）
- 只改 WiFi 为模块，其余内建 → 开机正常
- 模块加载成功，但 WiFi HAL 仍失败

### 尝试 3：设备节点名修复
- **发现**：`#ifdef MODULE` 时 `WLAN_MODULE_NAME = module_name(THIS_MODULE)`
- 导致 `/dev/qca_cld3_qca6390` 而非 HAL 期望的 `/dev/wlan`
- 改为 `#define WLAN_MODULE_NAME "wlan"` → `/dev/wlan` 出现

### 尝试 4：固件路径修复
- **发现**：`MULTI_IF_NAME` 被设为模块名，固件路径变成 `wlan/qca_cld/qca_cld3_qca6390/WCNSS_qcom_cfg.ini`（不存在）
- 实际固件在 `/vendor/firmware/wlan/qca_cld/qca6390/WCNSS_qcom_cfg.ini`（真实文件）和 `wlan/qca_cld/WCNSS_qcom_cfg.ini`（软链接）
- 改 `MULTI_IF_NAME="qca6390"` → 固件路径正确
- **同时发现**：`modules.dep` 缺失导致 `modprobe` 找不到模块

### 结果
```
wlan: Loading driver v5.2.022.12B
wlan0 connected to 8e:af:97:ac:c4:c0   ← WiFi 连接成功
```

**教训**：
1. 高通 qcacld 的模块名会拼进固件路径，改 MODNAME 必须同步改 MULTI_IF_NAME
2. Android WiFi HAL 通过 `/dev/wlan` 字符设备写 "ON"/"OFF" 控制驱动加载
3. 模块安装必须刷新 `modules.dep`，否则 `modprobe` 失败

---

## 阶段五：SELinux 与 init 崩溃

### 问题
- MIUI「设备内部出现了问题」告警
- init 进程 SIGABRT 崩溃于 `Service::SetProcessAttributesAndCaps()`

### 尝试
| 方案 | 结果 |
|---|---|
| `stock_defconfig` 伪装 `/proc/config.gz` | 告警仍在 |
| SELinux 完全禁用（`CONFIG_SECURITY_SELINUX=n`） | Android 起不来，进 fastboot |
| SELinux 默认 permissive + 拦截 `enforcing=1` 写入 | init 崩溃（状态机被破坏） |
| 放行写入，SELinux 变 Enforcing | init 仍崩溃（`setexeccon`/`ptrace` 被拒） |
| **`enforcing_enabled()` 永远返回 false** | init 不崩溃 + 实际 permissive |

### 结论
`enforcing_enabled()` 改为返回 false，同时 `enforcing_set()` 接受写入（init 以为成功）。

**教训**：Android init 依赖 SELinux 状态机的连续性，粗暴拦截写入会触发 `LOG(FATAL)`。

---

## 阶段六：Docker 嵌套

### 问题
Docker `docker.service` 启动失败，多轮排查：

| 错误 | 根因 | 修复 |
|---|---|---|
| `insecure registry ... invalid host` | daemon.json 写了 `https://` 前缀和 `/` 后缀 | 去掉 |
| `iptables: No chain/target/match by that name` | MIUI 残留链用 `quota2` match，容器 rootfs 缺 `libxt_quota2.so` | flush 残留链 |
| 同上（Host 网络模式） | 共享 netns，MIUI 规则必然可见 | `flush-miui-iptables.sh` 持久化 |

### 结果
```
Docker daemon ... storage-driver=vfs version=26.1.4
Daemon has completed initialization
```

**教训**：
1. Host 网络模式下，宿主 MIUI 的 iptables 规则会污染容器
2. `quota2` match 缺失导致 iptables 整表校验失败，连 `-N` 都不行
3. Docker 4.19 内核建议 `iptables-legacy` + `vfs` + `cgroupfs`

---

## 阶段七：交付

### 已验证
- ✅ 内核 4.19.325 + Droidspaces 全功能
- ✅ WiFi 连接
- ✅ Droidspaces 容器（Ubuntu 24.04 + systemd）
- ✅ Docker（Host 模式 + flush）
- ✅ Magisk 保留

### 已知未解决
- ⚠️ MIUI「设备内部出现了问题」告警（init SIGABRT）
- ⚠️ autofs4 无害警告
- ⚠️ Host 模式下每个容器需 flush iptables

---

## 附：内核配置要求对照表

| 配置项 | 原厂 defconfig | 最终状态 | 作用 |
|---|---|---|---|
| `PID_NS` | is not set | y | 容器必需 |
| `SYSVIPC` | 缺失 | y | IPC namespace |
| `USER_NS` | 缺失 | y | Docker/嵌套容器 |
| `DEVTMPFS` | 缺失 | y | 容器 /dev |
| `CGROUP_DEVICE` | 缺失 | y | 容器必需 |
| `CFS_BANDWIDTH` | 缺失 | y | --cpus |
| `CGROUP_PIDS` | 缺失 | y | --pids-limit |
| `ANDROID_PARANOID_NETWORK` | default y | 移除/不设 | 容器 NAT 网络 |
| `NF_TABLES_IPV4` | 缺失 | y | Docker iptables-nft |
| `AUTOFS4_FS` | is not set | y | systemd automount |
