# daed Quick-Settings Tile

一个无 Gradle 依赖的 Android 快捷设置磁贴系统应用，用于快捷控制 daed：

- **点按磁贴**：开启 / 关闭 **dae 代理**（daed WebUI 服务保持运行）
- **长按磁贴**：打开 WebUI `http://127.0.0.1:2023`。ColorOS 长按直接打开；原生 Android 呼出详情面板，点齿轮（⚙）打开
- 磁贴状态实时反映代理运行状态
- **无桌面图标**：应用不注册 `MAIN/LAUNCHER` 活动，只在快捷设置里以磁贴形式存在

> Android 的 `TileService` 无 `onLongClick` 钩子：长按磁贴由 SystemUI 处理。本模块在 `MainActivity` 上注册 `QS_TILE_PREFERENCES` intent：ColorOS 长按会直接拉起该活动（自动打开 WebUI），原生 Android 则从详情面板的齿轮进入 —— 因此即使没有 launcher 入口，长按开 WebUI 依旧可用。

通过 Magisk 模块以系统应用形式安装到 `system/app/DaedTile/DaedTile.apk`。应用在系统启动（`BOOT_COMPLETED`）时调用 `TileService.requestListeningState()` 注册磁贴，否则从未被用户启动过的系统磁贴应用不会进入 SystemUI 磁贴列表。

## 工作原理

- 磁贴通过 root（Magisk 超级用户授权，首次点按弹出授权框）执行 `su -c ...`
- 开启代理：`pkill -USR2 -f '[d]aed run'` → daed 复用 WebUI 的 `run` 逻辑加载配置并启动 eBPF 代理
- 停止代理：`pkill -USR1 -f '[d]aed run'` → daed 加载空配置卸载 eBPF 代理，**WebUI 进程不退出**
- daed 未运行时：磁贴直接以 `nohup daed run -c /data/adb/daed` 拉起守护进程
- 代理状态：daed 写入/删除标记文件 `/data/adb/daed/.dae-stopped`，磁贴用 `test -f` 快速读取

对应 dae-wing 的改动见 `../patches/dae-wing-proxy-toggle-android.patch`（SIGUSR1/SIGUSR2 信号处理 + marker 同步）。

## 源码结构

```
AndroidManifest.xml          应用与 TileService 声明
build-apk.sh                 无 Gradle 构建脚本（aapt2 + javac + d8 + apksigner）
keystore/daed-tile.p12       固定签名密钥库（密码 android），保证 CI 构建签名一致
src/io/github/aumt/daedtile/
  Daedctl.java               root 命令封装（pgrep/pkill/nohup + marker 读取）
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
