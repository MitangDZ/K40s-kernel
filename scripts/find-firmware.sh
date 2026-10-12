#!/system/bin/sh
echo "=== 1. 查找 WCNSS_qcom_cfg.ini ==="
find /vendor/firmware /vendor/firmware_mnt /odm/firmware /etc/firmware /system/etc/firmware -name "*qcom_cfg*" -o -name "*WCNSS*" 2>/dev/null | head -30

echo ""
echo "=== 2. firmware 挂载点 ==="
mount | grep -i firmware
ls -la /firmware 2>/dev/null | head -5
ls -la /vendor/firmware 2>/dev/null | head -10
ls -la /vendor/firmware_mnt 2>/dev/null | head -10

echo ""
echo "=== 3. wlan 固件目录树 ==="
find /vendor/firmware /vendor/firmware_mnt -type d -name "*wlan*" -o -type d -name "*qca*" 2>/dev/null | head -20
ls -la /vendor/firmware/wlan 2>/dev/null
ls -la /vendor/firmware/wlan/qca_cld 2>/dev/null
ls -la /vendor/firmware_mnt/image/wlan 2>/dev/null

echo ""
echo "=== 4. 随便找几个 wlan 相关文件 ==="
find /vendor -iname "*wcnss*" -o -iname "*qca_cld*" -o -iname "wlan_mac*" 2>/dev/null | head -20

echo ""
echo "=== 5. SELinux 状态 ==="
getenforce 2>/dev/null
echo "--- 请把完整输出发回 ---"
