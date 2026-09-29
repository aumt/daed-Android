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
- 现在通过 `system/bin/daed-start` 启动：内置重复启动保护（扫 `/proc/*/comm`，不用 `pgrep`），启动后等待 **dae 该绑的接口都挂上 dae 的 tc 钩子**（该绑哪些读自 `wing.db`：`wan_interface` 为 `auto` 时是"所有带默认路由的接口"，点名时只查点名的那些；dae 是在 WebUI 就绪之后几秒才挂钩子的，所以要等——最多 30 秒，到点仍缺才重启一次 daemon。**"缺"必须是读得准的**：开机那阵内存紧张，`tc` 可能被信号杀掉、dump 被截断，或只 dump 出 filter 条目却查不到 `daed_` 名字，这三种都会读成 0，但它们是 `tc` 的问题、不是上行的事实——这时只把原始读数（退出码/行数/stderr）写进日志，**不重启**）；若磁贴里把 daed 关掉了（存在 `/data/adb/daed/.dae-stopped`），开机不会自动拉起
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

开机由 `service.sh` 启动 `system/bin/daed-watchdog`。它**不设定时重启**：每 `WATCH_INTERVAL`（默认 30s）只读一次状态，只在下列情况修复（`daed-stop` + `daed-start`）：

- **守护进程消失**：崩溃、被 OOM 或被手动杀掉；
- **WebUI 不响应**：`127.0.0.1:2023` 拿不到 200；
- **数据面失效**：流量已经不再被 dae 抓取（即“WebUI、节点延迟都正常，代理却静默失效”那个故障）。

### 数据面怎么判定

既不看日志里的 Bind 行，也不看“能不能打开被墙网站”：

- Bind 行是 **info 级**，daemon 首次 reload 后会按配置里的 `log_level` 重建 logger（本机是 `error`），这些行根本不会写进日志；
- 有些网络直连也能打开被墙站点，此时“探测能通”并不代表代理在工作。

所以改为**看效果**：以**非 root 的 uid（2000/shell）**访问一个被路由到代理的站点，同时观察 `dae0` 的收发计数 —— `dae0` 是 dae 决定接管一个流时把它送进去的 veth：

| 现象 | 结论 |
| --- | --- |
| 访问有响应 + `dae0` 计数增长 | 流被交给了 dae，数据面正常 |
| 访问有响应 + `dae0` 计数不动 | 流在抓取点被直接放行（没被接管）→ 数据面失效 → 修复 |
| 什么都不通 + `dae0` 计数不动 | 什么都没被抓取 → 数据面失效 → 修复 |

（uid 0 被 Android 补丁豁免，所以探针必须用非 root uid。）

**探测目标用固定 IP，不用域名。** 域名得由 root shell 自己解析，而 root 被 dae 豁免、查询直连出墙，被墙域名
拿回来的是**投毒地址**；投毒地址基本落在国内段，国内段按规则走**直连**，而直连的流在抓取点就被 `TC_ACT_OK`
放行、根本不进 `dae0`（`tproxy.c`：`we don't save state for direct+mark==0`）。用域名探测，**数据面完全正常
的机器也会被判成坏的**，然后被无谓重启。改用被墙域名的真实 IP（`PROBE_IPS`）后，“走代理”成为唯一可能：要么
`dae0` 动，要么数据面真的坏了。`PROBE_IPS` 会老化 —— 若在确认正常的机器上开始持续失败，从可用解析器
（走代理，或 DoH）重新取一份。

对照目标 `CTRL_*` 仍然解析：用国内域名只为判断“uid 2000 到底有没有网”，它即便被投毒也仍是可达的国内地址。

### 安全阀

- **连续两次才动手**：连续 `PROBE_FAILS`（默认 2）次探测异常才进入修复流程；
- **空闲门槛**：`dae0` 连续 `IDLE_SAMPLES × IDLE_SAMPLE_SEC`（默认 3×5s）没有流量才重启，不打断正在进行的下载；
- **冷却**：两次修复至少间隔 `HEAL_COOLDOWN`（默认 600s）；
- **事后校验 + 长退避**：修复后再探一次；若仍异常（例如节点本身挂了，重启治不了），退避 `BACKOFF`（默认 6h），不会反复重启；
- **闸门（按 dae 的绑定集合判断）**：取当前所有带默认路由的接口（`ip route show table all`，排除 `dummy0` / `lo`）；
  只要其中有**任意一个**是 dae 该绑的（读 `wing.db` 的 `wan_interface`/`lan_interface`；`auto` = 所有带默认路由
  的接口，此时必然放开）就照常探测，**全部都不是**时才认为”当前没有东西该被代理”而跳过。旧实现问的是
  “`wlan0` 是否 up 且未配置”——当上行切到 Wi-Fi、而 dae 的 tc/eBPF 钩子还留在开机时解析出的移动数据接口上时，
  这个判据恰好跳过了它本该抓到的故障：代理已死，看门狗却从不查看。”Wi-Fi 是 up 的”说明不了流量从哪个接口
  出去，默认路由才能。另：判据用 `ip route` 而不是 `operstate`，因为 Android 的 rmnet 接口在承载默认路由时
  报 `unknown`。想让 Wi-Fi 也走代理，在 WebUI 接口列表里勾选 `wlan0`（写进 `wing.db` 的 `wan_interface` /
  `lan_interface`），或保持 `wan_interface: “auto”`。
- **用户关闭期间**：`.dae-stopped` 标记存在时完全不动作。这条分支排在所有闸门（含退避）之前，所以
  `daed-stop` 是**先写标记、再发信号**：反过来写就留下一段「daemon 已死、声明还没立起来」的窗口，
  落在里面的 tick 会把用户刚关掉的 daemon 又拉起来（2026-09-29 实测 6 次，全部在点击后 6-18s，
  原因是 `daemon not running` / `web UI not answering`，没有一次是真故障）。同理，修复流程
  （`heal`）**不写**这个标记 —— 那不是用户关闭：写进去既会让这条分支永远命中，又会在启动失败时
  让看门狗从此不再修这个 daemon；修复途中用户若点了关闭，标记出现即中止本次启动。

日志：`/data/adb/daed/watchdog.log`（每次探测结果与修复原因都在里面）。

### 可调参数

写在 `/data/adb/daed/watchdog.conf`（`KEY=VALUE`）：

```sh
WATCH_INTERVAL=30
PROBE_INTERVAL=300
PROBE_FAILS=2
HEAL_COOLDOWN=600
BACKOFF=21600
IDLE_SAMPLES=3
IDLE_SAMPLE_SEC=5
NEVER_UPLINK_IFACES="dummy0 lo"
CONFIG_IFACE_KEYS="wan_interface lan_interface"
CONFIG_WAN_KEY="wan_interface"
PROBE_IPS="142.251.34.67 142.250.185.78 172.217.163.46"
PROBE_SNI="www.gstatic.com"
PROBE_URL="https://www.gstatic.com/generate_204"
PROBE_EXPECT="204"
CTRL_HOST="www.baidu.com"
CTRL_URL="https://www.baidu.com/"
```

## 🧰 模块内脚本

| 脚本 | 作用 |
| --- | --- |
| `system/bin/daed-start` | 启动 daemon（`setsid` 后台，含重复启动保护）、等待 WebUI 就绪、必要时开代理、确保看门狗在跑、等待 dae 该绑的接口都挂上 tc 钩子（按 `wing.db` 的 `wan_interface`/`lan_interface` 判断，最多等 30 秒，仍缺则重启一次；若 `tc` 读数不可信——非 0 退出、有 stderr、或有 filter 条目却查不到 `daed_` 名字——则只记日志不重启） |
| `system/bin/daed-stop` | `SIGTERM` 优雅停止（超时 `SIGKILL`）；**先写关闭标记、再发信号**；停不下来（`SIGKILL` 后仍有进程）则撤销标记并退出 1 |
| `system/bin/daed-watchdog` | 空闲时自愈：进程消失 / WebUI 无响应 / 数据面失效（`dae0` 判据） |
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
