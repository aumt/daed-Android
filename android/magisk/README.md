# daed Android Magisk 模块

daed Android Magisk 模块版本，可在已 root 的 Android 设备上以 Magisk 模块形式安装，开机自启 daed 后端，并通过快捷方式打开 Web 配置面板。

**适用平台：** Android arm64，需要已安装 Magisk（推荐 Magisk 24+）。

## 📦 安装

**前置条件：**

- 已 root 的 Android 设备
- 内核已开启 BPF 相关选项
- 已安装 Magisk/Kernelsu 或其他支持magisk模块的root管理器
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

dae 的路由规则依赖 `geosite.dat` 和 `geoip.dat`（例如 `geosite:cn`、`geoip:cn`、`geoip:private`），dae 只会从配置目录 `/data/adb/daed/` 查找这两份文件。

**模块已内置这两份数据**（gzip 压缩，约 5 MB），刷入时由 `customize.sh` 自动解压到 `/data/adb/daed/` —— 因此**装完即可离线使用 geosite/geoip 规则**，不再依赖开机时的网络。

- 数据源：`v2fly/domain-list-community`（→ `geosite.dat`）与 `v2fly/geoip`（→ `geoip.dat`），与 dae-core 解码格式一致
- 内置数据随模块版本刷新：仅当刷入的模块版本变化时才重新解压，重刷同一版本不会覆盖你手动更新过的文件
- **开机兜底**：`service.sh` 在后台检查，文件缺失时先解压内置副本，仍失败则从 v2fly 下载（跨数分钟重试，等待 WiFi 就绪）

**手动更新**：内置数据要等刷入新版本模块才会刷新。想立刻用上最新数据可手动下载 —— 之后需要重启设备、或开关一次磁贴让配置重新加载，daed 不会自动重载 geo 数据：

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
- 现在通过 `system/bin/daed-start` 启动：内置重复启动保护（`pgrep -x daed`），启动后还会校验 WAN 绑定是否正确；若磁贴里把 daed 关掉了（存在 `/data/adb/daed/.dae-stopped`），开机不会自动拉起
- 如需手动启动，可在终端执行：

```bash
su -c 'daed run -c /data/adb/daed &'
```

## 🎛️ 快捷设置磁贴（Quick-Settings Tile）

模块以系统应用形式安装一个 `dae` 磁贴，可快捷开关 **daed 守护进程**（dae 代理 + WebUI）：

- **点按磁贴**：开启 / 关闭 **daed 守护进程**（dae 代理 + WebUI）
  - 开启 = 全新启动 daed：会重新探测并绑定当前上网网卡，修复“WebUI、节点延迟都正常但代理静默失效”的状态
  - 关闭 = 停掉整个守护进程（WebUI 一并停止），并记住该状态（重启后不再自启）
  - 若守护进程在运行、只是代理被 WebUI 停掉，点按则只开启代理（`SIGUSR2`，面板保持运行）
- **长按磁贴**：打开 WebUI `http://127.0.0.1:2023`（服务监听 `0.0.0.0:2023`）。
- 磁贴图标实时反映代理状态（亮 = 正在代理，暗 = 未代理或守护进程未运行）
- **无桌面图标**：磁贴应用不注册启动器入口，只在快捷设置中作为磁贴存在

> 说明：Android 的 `TileService` 没有 `onLongClick` 钩子——长按磁贴由系统处理。模块在无 UI 的 `MainActivity` 上注册 `QS_TILE_PREFERENCES` 入口：经测试ColorOS 长按直接拉起该活动打开 WebUI，原生 Android 尚未测试。磁贴应用会在系统启动时自动注册（`BOOT_COMPLETED`），无需用户先手动打开应用。

**添加磁贴：** 下拉通知栏 → 快捷设置 → 点击编辑 → 把 `dae` 磁贴拖入。首次点按需要授予 root 权限，允许一次后即可静默工作。


## 🩺 自愈看门狗（daed-watchdog）

开机由 `service.sh` 启动 `system/bin/daed-watchdog`，它会在下列两种情况自动重启 daed（`daed-stop` + `daed-start`）：

- **守护进程消失**：崩溃、被 OOM 或被手动杀掉；
- **WAN 绑定失效**：Android 会重建移动数据网卡（`rmnet_data4` → `rmnet_data3/5`）并改变默认路由，而 dae 只在每次控制面构建时解析一次 WAN/LAN 网卡，于是它的 tc/eBPF 钩子留在旧网卡上 —— 应用流量不再被捕获，代理静默失效，而 WebUI、节点健康检查、日志看起来一切正常。

重启前会检查 `dae0` 的收发计数：连续约 15 秒没有流量才动手，避免打断正在进行的下载；两次修复之间有 10 分钟冷却。用户在磁贴里“关闭”期间（`.dae-stopped` 标记存在）看门狗完全不动作。

日志：`/data/adb/daed/watchdog.log`；`daed-start` 还会打印“默认路由网卡 vs dae 实际绑定的 WAN 网卡”的对比，便于确认绑定是否正确。

**它不会定时重启**：每 `WATCH_INTERVAL`（默认 30s）只读一次状态，只有“进程没了 / WebUI 不响应 / WAN 绑定失效”才动手，并且：

- **空闲门槛**：`dae0` 连续 `IDLE_SAMPLES × IDLE_SAMPLE_SEC`（默认 3×5s）没有流量才重启，避免打断下载；
- **冷却**：两次修复至少间隔 `HEAL_COOLDOWN`（默认 600s）；
- **迟滞**：某网卡必须持续 `STALE_GRACE`（默认 300s）未被绑定才算失效，避免 Wi-Fi/路由抖动触发重启；
- **事后校验 + 长退避**：修复后若绑定依旧缺失（说明重启也解决不了，例如 dae 本来就不绑该网卡），则退避 `BACKOFF`（默认 6h），不会每 10 分钟重启一次；
- **忽略名单**：`IGNORE_IFACES`（默认 `wlan0`）里的网卡不参与判定——本机 Wi-Fi 平时不走代理。
  但只要**你在 WebUI 的接口列表里勾选该网卡**（偶尔想让 Wi-Fi 也走代理的情况），它就会被要求绑定，不再被忽略。
  判断依据是 `wing.db` 里的接口配置键（默认 `wan_interface`、`lan_interface`，即 WebUI 的「WAN 接口」「LAN 接口」；值为 `auto` 时不包含任何具体网卡名）。键名可用 `CONFIG_IFACE_KEYS` 覆盖。
  如果你的 Wi-Fi 代理是靠 `auto` 自动探测生效、配置里并不会留下 wlan0，那么想让看门狗也校验它，就把 `wlan0` 从 `IGNORE_IFACES` 里去掉。

以上参数都可写在 `/data/adb/daed/watchdog.conf`（`KEY=VALUE`），例如：

```sh
WATCH_INTERVAL=30
HEAL_COOLDOWN=600
STALE_GRACE=300
BACKOFF=21600
IGNORE_IFACES="wlan0"
```

## 🧰 模块内脚本

| 脚本 | 作用 |
| --- | --- |
| `system/bin/daed-start` | 启动 daemon（`setsid` 后台，含重复启动保护）、等待 WebUI 就绪、必要时开代理、确保看门狗在跑、校验 WAN 绑定 |
| `system/bin/daed-stop` | `SIGTERM` 优雅停止（超时 `SIGKILL`）并写入关闭标记 |
| `system/bin/daed-watchdog` | 空闲时自愈：进程消失 / WAN 绑定失效 |
| `system/bin/daed-open` | 打开 WebUI |

磁贴点按时调用同一对 `daed-start` / `daed-stop`，因此手动点按与自动修复的行为完全一致。

**没看到磁贴？** 刷入模块并重启后，若快捷设置编辑列表里仍没有 `dae` 磁贴，手动安装一次磁贴应用即可（模块在安装时和开机时已尝试自动安装，以下命令为兜底）：

```bash
su -c 'pm install -r /data/adb/modules/daed/system/app/DaedTile/DaedTile.apk'
```

部分 ROM（如 ColorOS/OPPO）不会自动注册 Magisk 注入的 `system/app` 应用，需显式 `pm install` 一次后磁贴即会出现。

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
