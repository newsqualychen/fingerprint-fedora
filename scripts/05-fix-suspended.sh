#!/usr/bin/env bash
# 修复系统更新/睡眠后指纹传感器 "Cannot run while suspended" 的问题
#
# 原因：
#   1. 内核 USB autosuspend 空闲时挂起传感器
#   2. 系统 suspend/resume 后，libfprint 内部状态机可能停留在 suspended
#   3. 休眠与指纹识别撞上竞态，报 "Cannot run while suspended"
#
# 方案：
#   - udev 规则禁止该 USB 设备 autosuspend
#   - systemd sleep 钩子在系统恢复后重启 fprintd，重置设备状态
#   - 立即唤醒当前设备并重启 fprintd
#
# 用法: sudo bash 06-fix-suspended.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "请用 sudo 运行本脚本" >&2
    exit 1
fi

DEV=$(find /sys/bus/usb/devices -maxdepth 1 -type l 2>/dev/null | while read -r d; do
    [ -r "$d/idVendor" ] && grep -qi '06cb' "$d/idVendor" 2>/dev/null &&
    [ -r "$d/idProduct" ] && grep -qi '00b7' "$d/idProduct" 2>/dev/null &&
    basename "$d"
done | head -1)

if [ -z "$DEV" ]; then
    echo "未找到指纹传感器（06cb:00b7），设备可能未连接" >&2
    exit 1
fi

echo "找到传感器 USB 设备: $DEV"
echo "修复前: power/control=$(cat "/sys/bus/usb/devices/$DEV/power/control" 2>/dev/null) runtime_status=$(cat "/sys/bus/usb/devices/$DEV/power/runtime_status" 2>/dev/null)"

# 1. 立即唤醒当前设备
echo on > "/sys/bus/usb/devices/$DEV/power/control"

# 2. 永久 udev 规则：禁止该设备 autosuspend
cat > /etc/udev/rules.d/99-fingerprint-no-suspend.rules <<'EOF'
# HP Elite x2 G4 / Validity 06cb:00b7 fingerprint sensor
# Keep awake: libfprint reports "Cannot run while suspended" when the
# kernel autosuspends the sensor during idle.
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="06cb", ATTR{idProduct}=="00b7", ATTR{power/control}="on"
EOF

# 3. systemd sleep 钩子：resume 后重启 fprintd，清除 libfprint 的 suspended 状态
mkdir -p /usr/lib/systemd/system-sleep
cat > /usr/lib/systemd/system-sleep/99-fingerprint-resume <<'EOF'
#!/bin/bash
# Restart fprintd after suspend/resume so the fingerprint sensor is reinitialized.
if [ "$1" = "post" ]; then
    /usr/bin/systemctl try-restart fprintd.service >/dev/null 2>&1 || true
fi
EOF
chmod +x /usr/lib/systemd/system-sleep/99-fingerprint-resume

# 4. 重载规则并立即重启 fprintd
udevadm control --reload-rules
udevadm trigger --subsystem-match=usb --attr-match=idVendor=06cb --attr-match=idProduct=00b7 2>/dev/null || true
systemctl try-restart fprintd.service 2>/dev/null || true
sleep 1

echo "修复后: power/control=$(cat "/sys/bus/usb/devices/$DEV/power/control" 2>/dev/null) runtime_status=$(cat "/sys/bus/usb/devices/$DEV/power/runtime_status" 2>/dev/null)"
echo ""
echo "完成。未改动任何 RPM 文件，全部可回滚："
echo "  sudo rm /etc/udev/rules.d/99-fingerprint-no-suspend.rules"
echo "  sudo rm /usr/lib/systemd/system-sleep/99-fingerprint-resume"
echo ""
echo "请测试："
echo "  fprintd-verify $SUDO_USER"
echo "  sudo -k && sudo true && echo OK"
echo "  锁屏后按指纹解锁"
