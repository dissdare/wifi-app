# 主板控制台 (Board Control)

通过 WiFi / SSH 远程控制嵌入式 Linux 主板的 Flutter 应用。

手机连上主板的 WiFi 热点（或与主板处于同一局域网），应用会自动登录主板并进入交互式终端，执行诊断命令、查询 / 激活 4G 模块（ec20）等操作。

## 功能特性

- **自动登录（竞速连接）**：进入应用即并发尝试两个候选 IP（`192.168.1.1`、`125.126.127.1`），哪个先连上就进入控制台，另一个尝试自动取消；全部失败则提示可手动连接。
- **手动连接**：右上角「设置」按钮进入手动登录页，可自定义 IP / 端口 / 用户名 / 密码。
- **实时交互终端**：登录后进入基于 PTY 的交互式 shell，实时输入输出，支持中文等多字节字符（跨 chunk 增量解码），并过滤 ANSI 转义序列以显示干净的纯文本。
- **预设指令**：
  - 查看 ec20 激活状态
  - 激活 ec20
  - 中断当前操作（向终端发送 Ctrl+C）
- **连接状态指示**：右上角状态徽章，已连接显示绿色、断开显示红色；通过 keepalive 心跳（每 3 秒 ping + 4 秒超时）结合底层 socket 关闭监听，实时检测断连（主板断电 / WiFi 断开都能在数秒内感知）。
- **WiFi 网络绑定**：主板热点无外网时，Android 会将其判定为「无网络」并把流量切到蜂窝数据，导致连不上主板；应用通过 `bindProcessToNetwork` 主动把进程流量绑定到 WiFi。

## 技术栈

- Flutter 3.27（Dart 3）
- [dartssh2](https://pub.dev/packages/dartssh2) 2.11 —— 纯 Dart 的 SSH 客户端
- Material 3

## 目录结构

```
lib/
├── main.dart              # 应用入口
├── auto_login_screen.dart # 自动登录页（并发竞速连接两个 IP）
├── login_screen.dart      # 手动登录（设置）页
├── control_screen.dart    # 控制台（状态徽章 + 预设指令 + 交互终端）
├── ssh_service.dart       # SSH 封装：连接尝试 / 竞速 / keepalive / PTY shell
├── commands.dart          # 预设指令定义
└── network_binding.dart   # Android WiFi 网络绑定（MethodChannel）

android/app/src/main/kotlin/com/example/board_control/MainActivity.kt
                          # Android 原生侧：bindToWifi（bindProcessToNetwork 实现）
```

### 核心设计

- **连接尝试（`SshConnectionAttempt`）**：一次可取消的 SSH 连接尝试，`cancel()` 会销毁底层 socket 以中断进行中的连接 / 认证。
- **竞速（`raceConnect`）**：并发尝试多个候选，返回最先成功的一个，其余自动取消。
- **断连检测**：`client.done`（正常断开）+ 周期 keepalive ping（静默断开，如 WiFi 突然消失）。通知 listener 的时机放在 `close()` 之前，避免 `close()` 在底层已出错时抛异常而跳过通知。

## 使用说明

1. 手机连上主板的 WiFi 热点（SSID 如 `LZCZ2024060001T`）。
2. 打开应用，自动登录两个候选 IP，先成功者进入控制台。
3. 在终端输入命令，回车执行。
4. 点击「预设指令」快捷执行 ec20 相关操作（查看 / 激活状态、中断当前操作）。
5. 连接断开后，右上角状态徽章会在数秒内自动变为红色「已断开」。

### 默认连接信息

- 端口：22
- 用户名：root
- 密码：见 `lib/login_screen.dart` 中的默认值（`_passCtrl`）
- 候选 IP：`192.168.1.1`、`125.126.127.1`

> 默认凭据可在 `lib/auto_login_screen.dart`（自动登录）和 `lib/login_screen.dart`（手动登录）中修改。如设备会对外暴露，请修改默认密码并考虑校验 SSH 主机指纹。

## 构建与运行

```bash
flutter pub get
flutter run                    # 连接设备 / 模拟器运行
flutter build apk --debug      # 构建调试 APK
flutter build apk --release    # 构建发布 APK
```

产物位于 `build/app/outputs/flutter-apk/`。

## 注意事项

- **Android 模拟器无 WiFi 无线网卡**，WiFi 绑定（`bindProcessToNetwork`）的路径只能在真机上验证；但模拟器可通过主机网络（NAT）访问局域网内主板，用于验证 SSH / 终端流程。
- **主板 AP 无外网**时会被 Android 判定为「无网络」，需要 WiFi 网络绑定（已在 `network_binding.dart` + `MainActivity.kt` 实现）。
- 自动登录的两个候选 IP 对应不同网络位置下的同一类主板（如直连主板热点、或主板接入局域网），可按需增删。
