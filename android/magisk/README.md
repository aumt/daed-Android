# daed Android Magisk 模块

daed Android Magisk 模块版本，可在已 root 的 Android 设备上以 Magisk 模块形式安装，开机自启 daed 后端，并通过快捷方式打开 Web 配置面板。

**适用平台：** Android arm64，需要已安装 Magisk（推荐 Magisk 24+）。

## 📦 安装

**前置条件：**

- 已 root 的 Android 设备
- 已安装 Magisk
- 获取 `daed-magisk-<version>.zip` 安装包

**安装步骤：**

1. 将 `daed-magisk-<version>.zip` 传入手机存储
2. 打开 Magisk 应用 → 模块 → 从存储安装
3. 选择 zip 文件，等待安装完成
4. 重启设备

**安装后文件位置：**

- 二进制：`/data/adb/modules/daed/system/bin/daed`
- 快捷跳转脚本：`/data/adb/modules/daed/system/bin/daed-open`
- 磁贴系统应用：`/data/adb/modules/daed/system/app/DaedTile/DaedTile.apk`
- 配置目录：`/data/adb/daed`（含 `wing.db` 数据库、`daed.log` 日志）

## 🗂️ Geo 数据（geosite / geoip）

dae 的路由规则依赖 `geosite.dat` 和 `geoip.dat`（例如 `geosite:cn`、`geoip:cn`、`geoip:private`）。模块未内置这两份文件，`service.sh` 会在开机自启时检测缺失并自动从 v2fly 官方 Release 下载到配置目录 `/data/adb/daed/`（dae 会在此目录查找）。

- 下载源：`v2fly/domain-list-community`（→ `geosite.dat`）与 `v2fly/geoip`（→ `geoip.dat`），与 dae-core 解码格式一致
- 下载为 best-effort：若开机时网络未就绪导致下载失败，daed 仍会启动（此时若路由规则引用 geosite/geoip 则 reload 会失败并回滚），可在网络恢复后重启设备，或手动放置文件：

```bash
su -c 'curl -L -o /data/adb/daed/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat'
su -c 'curl -L -o /data/adb/daed/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat'
```

## 🚀 开机自启

模块通过 `service.sh` 在 Android 启动完成后自动拉起 daed 后端：

```bash
daed run -c /data/adb/daed
```

- 监听地址：`http://127.0.0.1:2023`
- 脚本内置重复启动保护（通过 `pgrep`/`pidof` 检测已有进程），无需担心多次执行导致端口冲突
- 如需手动启动，可在终端执行：

```bash
su -c 'daed run -c /data/adb/daed &'
```

## 🎛️ 快捷设置磁贴（Quick-Settings Tile）

模块以系统应用形式安装一个 `daed` 磁贴，可快捷开关 dae 代理：

- **点按磁贴**：开启 / 关闭 **dae 代理**（daed 的 WebUI 服务保持运行，不随代理停止）
- **长按磁贴**：打开 WebUI `http://127.0.0.1:2023`（服务监听 `0.0.0.0:2023`）
- 磁贴图标实时反映代理状态（亮 = 运行中，暗 = 已停止）

**添加磁贴：** 下拉通知栏 → 快捷设置 → 点击铅笔编辑 → 把 `daed` 磁贴拖入。首次点按会弹出 Magisk 超级用户授权对话框，允许一次后即可静默工作。

**实现原理：** 磁贴通过 root 向 daed 进程发送 `SIGUSR2`（开启代理）/ `SIGUSR1`（停止代理）信号，daed 内部复用与 WebUI 相同的 `run` 逻辑完成切换，因此数据库运行状态、代理状态保持一致；WebUI 进程始终存活。停止状态会写入标记文件 `/data/adb/daed/.dae-stopped`，供磁贴快速读取。

**卸载或升级后残留：** 若曾停止过代理，`/data/adb/daed/.dae-stopped` 标记文件与数据库运行状态共同决定下次开机的代理状态，无需手动清理。

## 🔗 快捷跳转配置地址

这是本模块的特色功能，提供两种方式快速打开 daed Web 配置面板。

### 方式一：命令行快捷跳转

在 Termux 或 adb shell 中执行：

```bash
daed-open
```

该脚本通过 `am start -a android.intent.action.VIEW -d http://127.0.0.1:2023` 调起系统默认浏览器打开配置面板。

### 方式二：桌面快捷方式配置

模块目录下预置 `shortcut.json`，第三方快捷方式工具（如「快捷方式」类 App）可读取该 JSON 生成桌面图标。

`shortcut.json` 内容示例：

```json
{
  "name": "daed",
  "url": "http://127.0.0.1:2023",
  "description": "Open daed web configuration panel"
}
```

## 🗑️ 卸载

- 在 Magisk 应用中删除模块即可
- 卸载时会自动停止 daed 进程
- 配置目录 `/data/adb/daed` 默认保留，如需彻底清理请手动删除：

```bash
rm -rf /data/adb/daed
```

## ⚠️ 注意事项

- 需要 root 权限
- 当前仅支持 Android arm64 架构
- eBPF 功能依赖内核版本（建议内核版本 >= 5.10，且开启 BPF 相关选项）
- 如遇网络异常，可尝试重启设备或检查 daed 配置
- 与 Linux 版本功能一致，但 Android 环境下部分高级网络配置可能受限
