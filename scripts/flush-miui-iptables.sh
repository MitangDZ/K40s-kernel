#!/bin/bash
# 清除 MIUI 残留 iptables 链（Host 网络模式下 Docker 必需）
# 用法: bash flush-miui-iptables.sh
# 一键安装 systemd service: bash flush-miui-iptables.sh --install

set -e

# 切到 legacy iptables（Ubuntu 24.04 默认 nft，Docker 4.19 内核需 legacy）
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

echo "=== 清除 filter 表 MIUI 残留链 ==="
iptables-legacy -t filter -F 2>/dev/null || true

for ch in \
  bw_INPUT bw_FORWARD bw_OUTPUT bw_costly_shared bw_costly_wlan0 \
  bw_data_saver bw_global_alert bw_happy_box bw_penalty_box \
  fw_INPUT fw_FORWARD fw_OUTPUT \
  nm_mdmprxy_doze_mode_skip nm_mdmprxy_iface_pkt_fwder \
  nm_qti_filter_ssdp_dropper oem_fwd oem_out \
  st_OUTPUT st_clear_caught st_clear_detect st_penalty_log st_penalty_reject \
  tc_limiter tc_mobile_limiter \
  tetherctrl_FORWARD tetherctrl_counters gms_wall
do
  iptables-legacy -t filter -X "$ch" 2>/dev/null || true
done

echo "=== 清除 nat / mangle 表残留 ==="
iptables-legacy -t nat -F 2>/dev/null || true
iptables-legacy -t nat -X 2>/dev/null || true
iptables-legacy -t mangle -F 2>/dev/null || true
iptables-legacy -t mangle -X 2>/dev/null || true

echo "=== 创建 Docker 所需链 ==="
iptables-legacy -t filter -N DOCKER 2>/dev/null || true
iptables-legacy -t filter -N DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
iptables-legacy -t filter -N DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
iptables-legacy -t filter -N DOCKER-USER 2>/dev/null || true

echo ""
echo "=== 当前 filter 表 ==="
iptables-legacy -t filter -L -n | head -12

# --install: 安装为 systemd service，开机自动执行
if [ "$1" = "--install" ]; then
  echo ""
  echo "=== 安装 systemd service ==="
  cat > /etc/systemd/system/flush-miui-iptables.service << 'EOF'
[Unit]
Description=Flush MIUI iptables chains that break Docker (Host netns)
Before=docker.service docker.socket
DefaultDependencies=no

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash /usr/local/sbin/flush-miui-iptables.sh
ExecStartPost=/bin/systemctl start docker

[Install]
WantedBy=multi-user.target
EOF

  cp "$0" /usr/local/sbin/flush-miui-iptables.sh
  chmod +x /usr/local/sbin/flush-miui-iptables.sh
  systemctl daemon-reload
  systemctl enable flush-miui-iptables
  echo "已安装并启用 flush-miui-iptables.service"
  echo "重启容器后 Docker 会自动启动"
fi

echo ""
echo "=== 重启 Docker ==="
systemctl restart docker 2>/dev/null || true
sleep 1
systemctl is-active docker && echo "Docker 运行中 ✅" || echo "Docker 未启动 ⚠️"
journalctl -u docker --no-pager -n 3 | tail -3
