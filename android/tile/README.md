# daed Quick-Settings Tile

一个无 Gradle 依赖的 Android 快捷设置磁贴系统应用，用于快捷控制 daed：

- **点按磁贴**：开启 / 关闭 **daed 守护进程**（dae 代理 + WebUI）
  - 开启：全新启动 daed（会重新探测并绑定当前上网网卡，修复“面板正常、代理静默失效”）；若守护进程在跑、只是代理被 WebUI 停掉，则只开启代理
  - 关闭：`SIGTERM` 停掉整个守护进程（WebUI 一并停止），并记住该状态（开机不再自启）
- **长按磁贴**：打开 WebUI `http://127.0.0.1:2023`。ColorOS 长按直接打开；原生 Android 呼出详情面板，点齿轮（⚙）打开
- 磁贴状态实时反映代理运行状态（亮 = 正在代理）
- **无桌面图标**：应用不注册 `MAIN/LAUNCHER` 活动，只在快捷设置里以磁贴形式存在

> Android 的 `TileService` 无 `onLongClick` 钩子：长按磁贴由 SystemUI 处理。本模块在 `MainActivity` 上注册 `QS_TILE_PREFERENCES` intent：ColorOS 长按会直接拉起该活动（自动打开 WebUI），原生 Android 则从详情面板的齿轮进入 —— 因此即使没有 launcher 入口，长按开 WebUI 依旧可用。

通过 Magisk 模块以系统应用形式安装到 `system/app/DaedTile/DaedTile.apk`。应用在系统启动（`BOOT_COMPLETED`）时调用 `TileService.requestListeningState()` 注册磁贴，否则从未被用户启动过的系统磁贴应用不会进入 SystemUI 磁贴列表。

## 工作原理

- 磁贴通过 root（Magisk 超级用户授权，首次点按弹出授权框）执行 `su -c ...`
- 开启：调用模块脚本 `system/bin/daed-start` → 以 `setsid` 拉起 daemon、等待 WebUI 就绪、必要时 `SIGUSR2` 开启代理、确保看门狗在跑，并校验 WAN 绑定是否覆盖当前默认路由网卡
- 关闭：调用模块脚本 `system/bin/daed-stop` → `SIGTERM` 优雅退出（daed 自己拆掉 veth/eBPF），超时才 `SIGKILL`，并写入 `.dae-stopped` 标记
- 守护进程在跑、代理被 WebUI 停掉：磁贴只发 `SIGUSR2`（`pkill -12 -x daed`）重新开启代理，不重启进程
- 代理状态：daed 写入/删除标记文件 `/data/adb/daed/.dae-stopped`，磁贴用 `test -f` 快速读取
- 同样的修复也会由 `daed-watchdog` 自动执行（见 `android/magisk/README.md`）：守护进程消失，或 WAN 绑定失效且 `dae0` 无流量时，自动重启 daed

对应 dae-wing 的改动见 `../patches/dae-wing-proxy-toggle-android.patch`（SIGUSR1/SIGUSR2 信号处理 + marker 同步）；现在 SIGUSR2 只用于“代理被停、进程仍在”这一种情况，磁贴的开/关由模块脚本完成。

## 源码结构

```
AndroidManifest.xml          应用与 TileService 声明
build-apk.sh                 无 Gradle 构建脚本（aapt2 + javac + d8 + apksigner）
keystore/daed-tile.p12       固定签名密钥库（密码 android），保证 CI 构建签名一致
src/io/github/aumt/daedtile/
  Daedctl.java               root 命令封装（调用模块脚本 daed-start / daed-stop，pgrep/pkill 查询状态）
  DaedTileService.java       磁贴（onClick / onLongClick）
  MainActivity.java          无 UI 入口：长按磁贴拉起后打开 WebUI 并立即退出
  BootReceiver.java          开机/更新后注册磁贴（requestListeningState）
res/                         strings / 图标
```

## 构建

脚本只依赖 **JDK** 与 **Android SDK build-tools + platform**，不需要 Gradle。

在任何 Linux 环境（含 CI 的 Debian runner）中：

```bash
# 1. 准备 SDK（示例：apt 安装 commandlinetools 后自动下载，或复用 CI 缓存）
export ANDROID_SDK_ROOT=/path/to/android-sdk
# 2. 构建
bash android/tile/build-apk.sh
# 产物：android/tile/build/daed-tile.apk（已签名）
```

在 GitHub Actions 中，`magisk-build.yml` 会自动执行 `bash android/tile/build-apk.sh` 并把 APK 打入 Magisk 模块 zip（`system/app/DaedTile/DaedTile.apk`）。

**签名：** 使用仓库内 `keystore/daed-tile.p12`（storepass/keypass 均为 `android`，PKCS12，RSA 2048）。系统应用升级必须保持同一签名，因此该密钥库随源码提交；若密钥库缺失，脚本会临时生成一次性密钥（仅适用于本地调试，系统应用升级会签名校验失败）。

## 注意

- `build/` 为构建产物目录，已被 `.gitignore` 排除。
