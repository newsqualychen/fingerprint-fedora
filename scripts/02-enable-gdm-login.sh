#!/usr/bin/env bash
# 启用 GDM 登录界面的指纹选项
#
# 背景: GNOME Shell 51 的 authServicesLegacy.js 里 _connectFingerprintManager()
#       有 `if (!this._reauthOnly) return;`，即指纹仅限锁屏解锁，登录界面被
#       有意禁用。此脚本用 GLib G_RESOURCE_OVERLAYS 覆盖相关 JS：
#         1) 去掉登录界面的“仅限锁屏”限制；
#         2) 修正上游图标名拼写 bug（fingerprint-auth-symbolic ->
#            auth-fingerprint-symbolic）。
#       不改动发行版 RPM 自带文件，可用 03-disable-gdm-login.sh 随时撤销。
#
# 用法: sudo bash 02-enable-gdm-login.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "请用 sudo 运行本脚本" >&2
    exit 1
fi

SHELL_SO=/usr/lib64/gnome-shell/libshell-51.so
RES_LEGACY=/org/gnome/shell/gdm/authServicesLegacy.js
RES_SERVICES=/org/gnome/shell/gdm/authServices.js
DEST_DIR=/usr/local/share/gnome-shell-fingerprint-login
DEST_LEGACY=$DEST_DIR/authServicesLegacy.js
DEST_SERVICES=$DEST_DIR/authServices.js
DROPIN=/etc/systemd/user/org.gnome.Shell@gdm.service.d/10-fingerprint.conf
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [ ! -f "$SHELL_SO" ]; then
    echo "找不到 $SHELL_SO，请确认 GNOME Shell 51 已安装" >&2
    exit 1
fi
if ! command -v gresource >/dev/null 2>&1; then
    echo "找不到 gresource 命令（glib2 包）" >&2
    exit 1
fi

# 0. 版本校验：确认系统 GNOME Shell 版本匹配（51）
if ! gresource list "$SHELL_SO" 2>/dev/null | grep -q "$RES_LEGACY"; then
    echo "警告：GNOME Shell 版本可能不是 51，补丁可能无法应用" >&2
fi

# 1. 从 GNOME Shell 的 gresource 中提取原始 JS
gresource extract "$SHELL_SO" "$RES_LEGACY" > "$TMP/legacy.orig.js"
gresource extract "$SHELL_SO" "$RES_SERVICES" > "$TMP/services.orig.js"

# 2. 打补丁
python3 - "$TMP/legacy.orig.js" "$TMP/legacy.js" \
                "$TMP/services.orig.js" "$TMP/services.js" <<'PYEOF'
import sys
legacy_in, legacy_out, services_in, services_out = sys.argv[1:5]

# 补丁 A: 去掉“指纹仅限锁屏”的限制
s = open(legacy_in, encoding='utf-8').read()
old = """    _connectFingerprintManager() {
        if (!this._reauthOnly)
            return;

        this._fingerprintManager = FingerprintManager.getFingerprintManager();"""
new = """    _connectFingerprintManager() {
        // Patched by fingerprint-fedora45: allow fingerprint at GDM login screen.
        // Upstream GNOME Shell 51 restricts this to the lock screen only.
        this._fingerprintManager = FingerprintManager.getFingerprintManager();"""
if old not in s:
    sys.exit("未找到预期代码（authServicesLegacy.js），GNOME Shell 版本可能不同；无法自动打补丁")
s = s.replace(old, new, 1)
open(legacy_out, 'w', encoding='utf-8').write(s)

# 补丁 B: 修正上游图标名拼写（让指纹图标能显示）
s = open(services_in, encoding='utf-8').read()
wrong = "iconName: 'fingerprint-auth-symbolic'"
right = "iconName: 'auth-fingerprint-symbolic'"
if wrong not in s:
    sys.exit("未找到预期代码（authServices.js），无法修正图标名；请报告此问题")
s = s.replace(wrong, right, 1)
open(services_out, 'w', encoding='utf-8').write(s)
print("已生成两个打过补丁的 JS 文件")
PYEOF

# 3. 安装补丁文件（不动发行版自带文件）
install -Dm0644 "$TMP/legacy.js"   "$DEST_LEGACY"
install -Dm0644 "$TMP/services.js" "$DEST_SERVICES"

# 4. 只给 GDM 的 gnome-shell unit 设置资源覆盖（多个用 : 分隔）
install -d "$(dirname "$DROPIN")"
cat > "$DROPIN" <<EOF
[Service]
Environment=G_RESOURCE_OVERLAYS=$RES_LEGACY=$DEST_LEGACY:$RES_SERVICES=$DEST_SERVICES
EOF

if command -v restorecon >/dev/null 2>&1; then
    restorecon -R "$DEST_DIR" "$(dirname "$DROPIN")" || true
fi

# 5. 验证 overlay 生效
if command -v gjs >/dev/null 2>&1; then
    cat > "$TMP/verify.js" <<'EOF'
const Gio = imports.gi.Gio;
function load(p) {
  let f = Gio.File.new_for_uri('resource:///org/gnome/shell/gdm/' + p);
  let [ok, c] = f.load_contents(null);
  return ok ? imports.byteArray.toString(c) : '';
}
let a = load('authServicesLegacy.js').includes('Patched by fingerprint-fedora45');
let b = load('authServices.js').includes("iconName: 'auth-fingerprint-symbolic'");
print(a && b ? 'OVERLAY_OK' : `OVERLAY_FAILED legacy=${a} services=${b}`);
EOF
    RESULT=$(G_RESOURCE_OVERLAYS="$RES_LEGACY=$DEST_LEGACY:$RES_SERVICES=$DEST_SERVICES" \
             /usr/bin/gjs "$TMP/verify.js" 2>/dev/null || true)
    if [ "$RESULT" = "OVERLAY_OK" ]; then
        echo "验证通过：两个 GResource overlay 均已生效"
    else
        echo "警告：overlay 自检未通过（$RESULT），请检查 SELinux/权限" >&2
    fi
fi

# 6. 如果 greeter 的 user manager 正在运行，尝试重载（重启后必然生效）
if [ -d /run/user/42 ]; then
    sudo -u gdm env XDG_RUNTIME_DIR=/run/user/42 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/42/bus \
        systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

echo "完成。请重新登录（或重启）后，在 GDM 界面选择用户使用指纹登录。"
echo "撤销补丁: sudo bash 03-disable-gdm-login.sh"
