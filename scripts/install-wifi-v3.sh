#!/system/bin/sh
# v3: 修复 modules.dep + 提前加载 + 验证 /dev/wlan
echo "========== 1. 备份 =========="
mkdir -p /sdcard/wifi_bak3
for f in qca_cld3_qca6390.ko qca_cld3_qca6490.ko modules.dep modules.alias modules.load modules.softdep; do
  cp -f /vendor/lib/modules/$f /sdcard/wifi_bak3/ 2>/dev/null
done
ls /sdcard/wifi_bak3/ 2>/dev/null

echo ""
echo "========== 2. 确认模块目录内容 =========="
ls -la /vendor/lib/modules/ | head -30

echo ""
echo "========== 3. 安装模块 =========="
mount -o rw,remount /vendor 2>/dev/null
cp -f /sdcard/wifi-module/qca_cld3_qca6390.ko /vendor/lib/modules/
cp -f /sdcard/wifi-module/qca_cld3_qca6490.ko /vendor/lib/modules/
chmod 644 /vendor/lib/modules/qca_cld3*.ko
ls -l /vendor/lib/modules/qca_cld3*.ko

echo ""
echo "========== 4. 重建 modules.dep / alias / load =========="
cd /vendor/lib/modules || exit 1

# depmod 若可用
if [ -x /vendor/bin/depmod ]; then
  echo "用 depmod..."
  /vendor/bin/depmod -b /vendor $(uname -r) 2>&1 | head -5
fi

# 无论 depmod 是否成功，确保关键条目存在
touch modules.dep modules.alias modules.load

# modules.dep: 必须有条目，否则 modprobe 找不到
grep -q "qca_cld3_qca6390.ko" modules.dep 2>/dev/null || {
  echo "qca_cld3_qca6390.ko:" >> modules.dep
  echo "qca_cld3_qca6490.ko:" >> modules.dep
  echo "已写入 modules.dep"
}

# modules.alias: init 用 qca_cld3_wlan 名字
for a in qca_cld3_qca6390 qca_cld3_qca6490 qca_cld3_wlan; do
  grep -q "alias $a " modules.alias 2>/dev/null || echo "alias $a qca_cld3_qca6390" >> modules.alias
done

# modules.load: 让下次开机更早加载
grep -q "qca_cld3_qca6390" modules.load 2>/dev/null || {
  echo "qca_cld3_qca6390" >> modules.load
  echo "已写入 modules.load"
}

echo "--- modules.dep ---"
cat modules.dep | tail -8
echo "--- modules.alias ---"
tail -6 modules.alias
echo "--- modules.load ---"
cat modules.load

echo ""
echo "========== 5. 热加载并验证 =========="
rmmod qca_cld3_qca6390 2>/dev/null
rmmod qca_cld3_qca6490 2>/dev/null
modprobe -a -d /vendor/lib/modules qca_cld3_qca6390 2>&1
echo "modprobe_exit=$?"

sleep 1
echo ""
echo "--- /dev/wlan ---"
ls -lZ /dev/wlan 2>/dev/null || echo "不存在"

echo ""
echo "========== 6. 手动触发驱动加载（关键测试）=========="
if [ -e /dev/wlan ]; then
  echo "写入 ON 到 /dev/wlan ..."
  echo -n "ON" > /dev/wlan 2>&1
  echo "write_exit=$?"
  sleep 2
  echo "--- dmesg 尾部（找 Loading driver / Turning On）---"
  dmesg | tail -40 | grep -iE "wlan|Loading|Turning|hdd|cnss|fail|error|Timed"
else
  echo "/dev/wlan 不存在，跳过"
fi

echo ""
echo "========== 7. 重启 wifi HAL =========="
stop vendor.wifi_hal_legacy 2>/dev/null
stop wificond 2>/dev/null
sleep 1
start vendor.wifi_hal_legacy 2>/dev/null
start wificond 2>/dev/null
echo "HAL 已重启，请现在去设置里开 WiFi"
