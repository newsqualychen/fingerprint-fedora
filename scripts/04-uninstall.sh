#!/usr/bin/env bash
# 卸载自定义指纹驱动，恢复系统原版 libfprint
# 用法: sudo bash 04-uninstall.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "请用 sudo 运行本脚本" >&2
    exit 1
fi

rm -f /usr/local/lib64/libfprint-2.so.2.0.0 \
      /usr/local/lib64/libfprint-2.so.2 \
      /usr/local/lib64/libfprint-2.so
rm -rf /usr/local/share/libfprint/validity
rm -f /etc/systemd/system/fprintd.service.d/10-validity.conf
rmdir --ignore-fail-on-non-empty /etc/systemd/system/fprintd.service.d 2>/dev/null || true
rm -f /etc/udev/rules.d/99-fingerprint-no-suspend.rules
rm -f /usr/lib/systemd/system-sleep/99-fingerprint-resume

systemctl daemon-reload
systemctl try-restart fprintd.service || true

echo "已卸载自定义指纹驱动。传感器上已录入的指纹数据不会被删除，"
echo "但系统原版 libfprint 不支持该设备，fprintd-list 将再次显示 No devices available。"
