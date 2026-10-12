# Redmi K40S (munch) 自定义内核 — Droidspaces 适配

为 **Redmi K40S（代号 munch，SM8250）** 编译的自定义内核，满足 [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) 容器运行时的全部内核要求。

## 当前状态

| 功能 | 状态 |
|---|---|
| 内核版本 | 4.19.325（Flicker sm8250 tree） |
| Droidspaces 全功能配置 | ✅ namespace / cgroup / overlay / NAT / 资源限制 |
| WiFi（qca6390） | ✅ 已连接，固件路径修复 |
| SELinux | 强制 permissive（不崩溃 init） |
| Docker 嵌套 | ✅ Host 网络模式 + flush 脚本 |
| KernelSU | 可选（`vendor/ksu.config`） |
| MIUI「内部问题」告警 | 已知问题，暂未修复 |
| autofs4 警告 | 无害（内建后 systemd 找不到 .ko） |

## 目录结构

```
config/
  droidspaces.config          Droidspaces 必需配置 fragment
  droidspaces-extras.config   可选增强（IPv6 NAT / UFW / 资源限制）
  disable-selinux.config      SELinux permissive
  container-fixes.config      autofs4 等容器修复
  docker-iptables.config      NF_TABLES_IPV4 等 Docker 支持
  no-lto.config               关闭 LTO（内存不足）
  wifi-module.config          WiFi 模块化配置
  modules.config              全模块化配置（实验性）

patches/
  01.fix_kernel_panic_in_xt_qtaguid.patch    Droidspaces non-GKI 补丁 1
  02.fix_restore_cgroup_file_prefix_handling.patch  Droidspaces non-GKI 补丁 2
  011.stock_defconfig.patch    消除「设备内部出现问题」告警

scripts/
  env.sh                      本地环境变量（source 使用）
  install-wifi-v3.sh          WiFi 模块安装（含 modules.dep 修复）
  flush-miui-iptables.sh      清除 MIUI iptables 残留（Host 网络 Docker 必需）
  find-firmware.sh            固件路径诊断
```

## 内核源码与工具链

**不入库**（体积过大），获取方式：

```bash
# 内核源码（Flicker sm8250 tree，含 techpack/Droidspaces 支持）
git clone --depth 1 --branch seventeen \
  https://github.com/Flicker-Android-Devices/kernel_xiaomi_sm8250.git source-flicker

# 工具链（clang-r399163b + Arm GNU binutils）
# 见 env.sh 中的路径约定，放到 toolchains/ 下
```

## 构建方法

```bash
source env.sh
cd source-flicker

# 1. 合并配置
make O=../out-flicker ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  CC=clang CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- \
  HOSTCC=gcc HOSTCXX=g++ \
  munch_defconfig \
  arch/arm64/configs/vendor/droidspaces.config \
  ../config/droidspaces-extras.config \
  ../config/container-fixes.config \
  ../config/docker-iptables.config \
  ../config/disable-selinux.config \
  ../config/no-lto.config

make O=../out-flicker ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  CC=clang CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- \
  HOSTCC=gcc HOSTCXX=g++ olddefconfig

# 2. 编译（WiFi 模块化）
# 需先改 Kbuild: MODNAME=wlan→qca_cld3_qca6390，MULTI_IF_NAME=qca6390
# 以及 security.h: enforcing_enabled() 返回 false
make O=../out-flicker ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  CC=clang CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- \
  HOSTCC=gcc HOSTCXX=g++ -j$(nproc)

# 3. 打包 boot.img（magiskboot 或 mkbootimg）
# 保留原厂 ramdisk，只替换 kernel
```

## 关键源码补丁

### 1. WiFi 固件路径（`Kbuild`）
模块名被拼进固件路径导致找不到 `WCNSS_qcom_cfg.ini`：
```makefile
# 修改前: ccflags-y += -DMULTI_IF_NAME=\"$(CHIP_NAME)\"  (CHIP_NAME=模块名)
# 修改后: ccflags-y += -DMULTI_IF_NAME=\"qca6390\"      (固件真实路径)
```

### 2. WiFi 设备节点名（`wlan_hdd_main.c`）
```c
// 修改前: #ifdef MODULE → module_name(THIS_MODULE)  → /dev/qca_cld3_qca6390
// 修改后: #define WLAN_MODULE_NAME "wlan"             → /dev/wlan（HAL 期望）
```

### 3. SELinux 永久 permissive（`security.h`）
```c
static inline bool enforcing_enabled(struct selinux_state *state)
{
    return false;  // init 可写 enforcing=1，但检查永远视为 permissive
}
```

### 4. stock_defconfig（`kernel/Makefile`）
`/proc/config.gz` 输出原厂配置，骗过 MIUI 检查（部分生效）。

## 安装

```bash
# 1. TWRP 刷 new-boot.img → Boot 分区
# 2. 安装 WiFi 模块（保留原厂 modules.dep 兼容）
bash install-wifi-v3.sh

# 3. Docker（Host 网络模式）
bash flush-miui-iptables.sh --install
```

## 已知问题

1. **MIUI「设备内部出现了问题」告警**  
   根因是 init `SetProcessAttributesAndCaps` SIGABRT。已尝试 stock_defconfig 伪装 + SELinux 调整，告警仍在。待查。

2. **`Failed to find module 'autofs4'`**  
   autofs4 已内建（`=y`），systemd 找不到 `.ko` 文件的无害警告。

3. **Host 网络模式下 Docker**  
   必须运行 `flush-miui-iptables.sh` 清除 MIUI 的 `quota2` 残留链，否则 iptables 校验失败导致 Docker 起不来。

## License

### 本仓库原创内容
`scripts/`、`config/`、文档 — **MIT License**（见 [LICENSE](LICENSE)）

### 内核源码
Linux 内核遵循 **GPL-2.0-only**（`GPL-2.0 WITH Linux-syscall-note`）。  
源码来自 [Flicker-Android-Devices/kernel_xiaomi_sm8250](https://github.com/Flicker-Android-Devices/kernel_xiaomi_sm8250)。

### 第三方补丁（协议注意）

| 补丁 | 来源 | 协议 | 说明 |
|---|---|---|---|
| `patches/01.fix_kernel_panic_in_xt_qtaguid.patch` | [Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS) | **GPL-3.0** | 对 GPL-2.0 内核的修改 |
| `patches/02.fix_restore_cgroup_file_prefix_handling.patch` | [Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS) | **GPL-3.0** | 对 GPL-2.0 内核的修改 |
| `patches/011.stock_defconfig.patch` | [Android-Kernel-Tutorials](https://github.com/ravindu644/Android-Kernel-Tutorials) | **GPL-3.0** | 对 GPL-2.0 内核的修改 |

**协议兼容性说明**：GPL-3.0 与 GPL-2.0-only 存在不兼容问题。这些补丁以**注明出处**的方式收录，方便实践使用。若需严格合规，请从上游获取补丁，或联系原作者确认授权方式。

每个补丁文件头部均标注了来源、上游路径和原协议。

## 致谢与工具说明

本项目在开发过程中使用了 **AI 辅助编程工具（MiMoCode / Claude）** 完成以下工作：

- 内核配置需求分析（Droidspaces 文档比对 defconfig）
- 编译环境搭建与工具链选型
- 源码补丁编写（WiFi 固件路径、设备节点名、SELinux、stock_defconfig）
- 问题诊断与日志分析（init 崩溃、Docker iptables、WiFi HAL）
- 脚本编写（安装、flush、诊断）
- 文档编写

AI 工具参与了代码与文档的编写，但所有关键决策、真机测试、问题定位均由维护者完成。构建方法与补丁逻辑已人工审查并实测验证。
