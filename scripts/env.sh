#!/bin/bash
# 本地环境变量 —— source 本脚本生效，不写入全局配置
# 用法: source scripts/env.sh
# 清理: 直接删除项目目录即可

# 自动推导项目根目录（无论从哪里 source）
K40S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 主编译器：AOSP clang-r399163b（与 source/build.config.common 一致）
export PATH="${K40S_ROOT}/toolchains/clang-r399163b/bin:${PATH}"

# binutils：本地符号链接，前缀 aarch64-linux-gnu-
export PATH="${K40S_ROOT}/toolchains/local-binutils/bin:${PATH}"

# Python shim（gcc-wrapper 等需要）
export PATH="${K40S_ROOT}/toolchains/local-shims:${PATH}"

# 打包工具
export PATH="${K40S_ROOT}/toolchains/mkbootimg:${PATH}"

export K40S_ROOT
export KERNEL_SRC="${K40S_ROOT}/source-flicker"
export KERNEL_OUT="${K40S_ROOT}/out-flicker"

echo "[env.sh] K40S_ROOT=${K40S_ROOT}"
echo "[env.sh] clang: $(command -v clang)"
