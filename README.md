# HP Elite x2 G4 指纹解锁（Fedora）

让 HP Elite x2 G4 上的 `06cb:00b7 Synaptics/Validity` 指纹传感器在 Fedora 上工作，支持：

- 🔓 指纹解锁 GNOME 锁屏
- 🔐 `sudo` 指纹认证
- 🖥️ GDM 登录界面指纹登录（GNOME Shell 51 默认禁用，本项目用可逆补丁启用）

## 当前支持

| Fedora 版本 | GNOME Shell | Release 标签 | 状态 |
|---|---|---|---|
| 45 | 51 | `v1.0.0-fedora45` | ✅ 已验证 |

> 其他 Fedora 版本尚未验证。欢迎在 Issues 里反馈测试结果，或在 workflow_dispatch 里手动触发构建尝试。

## 背景

Fedora 自带的 libfprint **不支持**这个传感器（`fprintd-list` 显示 `No devices available`）。本项目使用上游未合并的 [libfprint MR !626](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/626) 原生驱动，已在同芯片的 HP EliteBook G6 系列上验证。

GNOME Shell 51 有意把指纹限制在锁屏界面（登录界面不显示指纹选项），本项目用一个**可逆的 GResource overlay 补丁**去掉这个限制，不修改任何发行版 RPM 文件。

> ⚠️ **风险提示**：驱动首次使用可能需要与传感器配对，**会擦写芯片上的指纹数据**，双系统下 Windows Hello 指纹可能失效。这是实验性、未合并的上游代码。

## 下载

到 [Releases 页面](../../releases) 下载对应你 Fedora 版本的包，例如 `fingerprint-validity-v1.0.0-fedora45.tar.gz`。

> 编译产物与 Fedora 版本绑定（glibc 等依赖），请下载与系统版本匹配的包。

## 安装步骤

### 0. 确认指纹功能已启用（Fedora 默认已启用）

```bash
authselect current | grep with-fingerprint
```

如果没有输出，先启用：

```bash
sudo authselect enable-feature with-fingerprint
```

### 1. 安装驱动

```bash
tar -xzf fingerprint-validity-v*.tar.gz
cd fingerprint-validity-v*
sudo bash scripts/01-install.sh
```

确认设备被识别：

```bash
fprintd-list $USER
# 应显示: found 1 devices / Validity VCSFW Fingerprint Sensor
```

### 2. 录入指纹（本人按传感器）

```bash
fprintd-enroll -f right-index-finger $USER
```

按提示多次按压传感器直到成功。验证：

```bash
fprintd-verify $USER    # 录入的手指 -> verify-match
```

测试 sudo 指纹认证：

```bash
sudo -k && sudo true && echo OK
```

### 3. 启用 GDM 登录界面指纹（可选）

```bash
sudo bash scripts/02-enable-gdm-login.sh
```

**重新登录或重启**后，在 GDM 界面点选用户名，应能看到指纹选项，按手指即可登录。密码登录仍可用（回退）。

> 注：指纹登录**不会**解锁 GNOME keyring，应用首次请求 keyring 时仍会要密码，这是正常现象。

## 卸载 / 回滚

```bash
sudo bash scripts/03-disable-gdm-login.sh   # 撤销 GDM 登录补丁
sudo bash scripts/04-uninstall.sh           # 卸载自定义驱动
```

只写入 `/usr/local`、`/etc/systemd/system/fprintd.service.d/` 和 `/etc/systemd/user/org.gnome.Shell@gdm.service.d/`，**不覆盖发行版 RPM 文件**。传感器上已录入的指纹不会被删除。

## 从源码构建

Release 包是 CI 在对应 Fedora 容器里编译的。如需自行构建：

```bash
sudo dnf -y install gcc gcc-c++ meson ninja-build make python3 \
    glib2-devel libgusb-devel libgudev-devel openssl-devel \
    pixman-devel systemd-devel git

git clone https://gitlab.freedesktop.org/libfprint/libfprint.git /tmp/libfprint
cd /tmp/libfprint
git fetch origin refs/merge-requests/626/head
git checkout FETCH_HEAD
meson setup build --prefix=/usr/local --libdir=lib64 --buildtype=release \
    -Dintrospection=false -Ddoc=false -Dgtk-examples=false \
    -Dinstalled-tests=false -Dudev_rules=disabled -Dudev_hwdb=disabled
meson compile -C build
```

数据文件来自 [libfprint-validity-data](https://gitlab.freedesktop.org/ggiesen/libfprint-validity-data)，运行 `python3 generate_data.py` 生成。

## 添加新 Fedora 版本支持

1. 确认该版本的 GNOME Shell 里 GDM 指纹补丁逻辑是否变化（检查 `authServicesLegacy.js` 的 `_connectFingerprintManager`）
2. 在 `.github/workflows/release.yml` 的 `workflow_dispatch` options 里加入新版本号
3. 从 Actions 页面用 workflow_dispatch 手动触发构建测试
4. 验证通过后，打 tag 格式 `v1.0.0-fedora<版本>`（如 `v1.0.0-fedora46`）触发正式 Release

## 致谢

- [libfprint MR !626](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/626) by the libfprint community
- [libfprint-validity-data](https://gitlab.freedesktop.org/ggiesen/libfprint-validity-data)
- GNOME Shell / Fedora 项目
