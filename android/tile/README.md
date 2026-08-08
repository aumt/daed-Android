# daed Quick-Settings Tile

一个无 Gradle 依赖的 Android 快捷设置磁贴系统应用，用于快捷控制 daed：

- **点按磁贴**：开启 / 关闭 **dae 代理**（daed WebUI 服务保持运行）
- **长按磁贴**：呼出系统磁贴详情面板，点齿轮（⚙）打开 WebUI `http://127.0.0.1:2023`
- 磁贴状态实时反映代理运行状态

> Android 的 `TileService` 无 `onLongClick` 钩子：长按磁贴由 SystemUI 展示详情面板。本模块通过 `QS_TILE_PREFERENCES` intent 把详情面板的齿轮入口指向主界面（自动打开 WebUI），这是原生框架下最接近"长按开 WebUI"的实现。

通过 Magisk 模块以系统应用形式安装到 `system/app/DaedTile/DaedTile.apk`。

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
  MainActivity.java          启动入口：状态页 + 打开 WebUI 按钮
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

- 本目录不在 Windows 本机构建，只写源码，构建由 CI 与本地 Linux 环境完成。
- `build/` 为构建产物目录，已被 `.gitignore` 排除。
