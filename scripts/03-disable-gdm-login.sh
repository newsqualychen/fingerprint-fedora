#!/usr/bin/env bash
# 撤销 GDM 登录指纹补丁，恢复 GNOME Shell 原版行为
# 用法: sudo bash 03-disable-gdm-login.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "请用 sudo 运行本脚本" >&2
    exit 1
fi

rm -f /etc/systemd/user/org.gnome.Shell@gdm.service.d/10-fingerprint.conf
rmdir --ignore-fail-on-non-empty /etc/systemd/user/org.gnome.Shell@gdm.service.d 2>/dev/null || true
rm -rf /usr/local/share/gnome-shell-fingerprint-login

if [ -d /run/user/42 ]; then
    sudo -u gdm env XDG_RUNTIME_DIR=/run/user/42 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/42/bus \
        systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

echo "已撤销 GDM 登录指纹补丁。重新登录或重启后生效。"
