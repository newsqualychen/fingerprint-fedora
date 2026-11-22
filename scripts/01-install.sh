#!/usr/bin/env bash
# 一键安装：自定义 libfprint 驱动 + Validity 数据文件 + fprintd drop-in
#
# 用法: sudo bash 01-install.sh
# 说明: 从本 Release 包内的 lib/ 和 data/ 目录安装，不覆盖发行版 RPM 文件。
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "请用 sudo 运行本脚本" >&2
    exit 1
fi

# 定位包根目录（脚本所在目录的上一级）
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LIB_SRC="$ROOT/lib/libfprint-2.so.2.0.0"
DATA_DIR="$ROOT/data/validity"

if [ ! -f "$LIB_SRC" ]; then
    echo "找不到 $LIB_SRC，请确认下载并解压了完整的 Release 包" >&2
    exit 1
fi
if [ ! -d "$DATA_DIR" ]; then
    echo "找不到 $DATA_DIR" >&2
    exit 1
fi

# 1. 自定义 libfprint 放到 /usr/local/lib64（系统 RPM 里的原版保持不变）
install -d /usr/local/lib64
install -m 0755 "$LIB_SRC" /usr/local/lib64/libfprint-2.so.2.0.0
ln -sfn libfprint-2.so.2.0.0 /usr/local/lib64/libfprint-2.so.2
ln -sfn libfprint-2.so.2.0.0 /usr/local/lib64/libfprint-2.so

# 2. 传感器数据文件
install -d /usr/local/share/libfprint/validity
cp -a "$DATA_DIR"/. /usr/local/share/libfprint/validity/

# 3. 只让 fprintd 使用自定义库，避免影响系统里其他程序
install -d /etc/systemd/system/fprintd.service.d
cat > /etc/systemd/system/fprintd.service.d/10-validity.conf <<'EOF'
[Service]
Environment=LD_LIBRARY_PATH=/usr/local/lib64
EOF

if command -v restorecon >/dev/null 2>&1; then
    restorecon -R /usr/local/lib64/libfprint-2.so* \
                  /usr/local/share/libfprint \
                  /etc/systemd/system/fprintd.service.d || true
fi

systemctl daemon-reload
systemctl try-restart fprintd.service || true

echo "驱动安装完成。"
echo "请确认 PAM 已启用指纹: authselect current | grep with-fingerprint"
echo "然后运行: fprintd-enroll -f right-index-finger ${SUDO_USER:-squaly}"
