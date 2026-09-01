# 主板控制台 (Board Control)

通过 **WiFi 局域网直连** 或 **frp 内网穿透** 远程控制嵌入式 Linux 主板的 Flutter 应用。

手机打开应用后提供两种连接方式：连接主板自带 WiFi 热点走局域网 SSH，或通过 frp 服务器从任意网络（蜂窝 / 外网）反向穿透到主板。连接成功后进入一个 **真正的交互式终端**（基于 PTY + xterm 终端模拟器），可直接输入命令、`cd` 切换目录，并带有一键预设指令（查询 / 激活 4G 模块 ec20）和实时连接状态指示。

---

## 功能特性

### 双入口首页

打开应用后首页居中显示两个按钮：

| 按钮 | 行为 |
|---|---|
| **wifi连接主板** | 走局域网 SSH 直连（见下） |
| **远程连接主板** | 走 frp 内网穿透（见下） |

### WiFi 直连（局域网）

- **自动登录（竞速连接）**：进入即并发尝试两个候选 IP（`192.168.1.1`、`125.126.127.1`），哪个先连上就进入控制台，另一个尝试自动取消；全部失败可手动连接。
- **手动连接**：右上角「设置」按钮进入手动登录页，可自定义 IP / 端口 / 用户名 / 密码。
- **WiFi 网络绑定**：主板热点无外网时，Android 会把它判定为「无网络」并把流量切到蜂窝数据，导致连不上主板；应用通过 `bindProcessToNetwork` 主动把进程流量绑定到 WiFi，保证 socket 走 WiFi。

### 远程连接（frp 内网穿透）

针对主板通过 frp 客户端反向注册到公网 frp 服务器的场景。远程配置页包含五个可编辑字段：

| 字段 | 默认值 | 说明 |
|---|---|---|
| frp服务器地址 | `http://concrete-frp.letsgrp.com` | 会自动剥离 `http://` 前缀，只取主机名 |
| frp代理端口 | `17011` | frp 服务器 tcpmux / httpconnect 端口 |
| 设备序列号 | `LZCZ2025080001` | 设备唯一标识，作为 frp 路由键 |
| 用户名 | `root` | 目标主板的 SSH 用户名 |
| 密码 | `Lets@002398` | 目标主板的 SSH 密码（掩码显示） |

连接成功后进入与 WiFi 相同的控制台页面，但**不显示** ec20 预设按钮（只保留「中断当前操作」）。

> **frp 连接协议说明**（重要）：本项目的主板 frpc 使用 `type = "tcpmux"` + `multiplexer = "httpconnect"`。这不是「直接 SSH 到 frp 端口」，而是要先做一次 **HTTP CONNECT 握手**，用设备序列号作为 `Host` 头路由到对应主板，之后才在同一 socket 上跑标准 SSH。因此：
> - 设备序列号是 **frp 路由键**（HTTP Host），**不是** SSH 用户名的一部分；
> - SSH 用户名就是 `root`，与序列号不拼接。
>
> 对应主板上的 frpc 配置形如：
> ```toml
> serverAddr = "concrete-frp.letsgrp.com"
> serverPort = 17010
>
> [[proxies]]
> name = "LZCZ2025110078"
> type = "tcpmux"
> multiplexer = "httpconnect"
> customDomains = ["LZCZ2025110078"]
> localIP = "127.0.0.1"
> localPort = 22
> ```

### 交互式终端（真终端）

登录后进入基于 **xterm** 终端模拟器的交互式 shell（而非「输出框 + 输入框」）：

- 输入直接跟在提示符 `root@LZCZ2025110078:~#` 后面，回车执行命令；
- `cd` 切换目录，提示符路径自动跟着变；
- 支持 ANSI 转义序列解析、光标定位、回显、退格、tab 补全、历史滚动；
- 支持中文等多字节字符（跨 chunk 增量解码）。

### 预设指令

顶部「预设指令」面板（`ActionChip` 按钮）：

- **查看 ec20 激活状态**：查询主板 4G 模块 usbnet 激活状态
- **激活 ec20**：下发 AT 命令激活 ec20
- **中断当前操作**：向终端发送 Ctrl+C

> WiFi 连接显示全部三个按钮；远程连接只显示「中断当前操作」。

### 连接状态指示

右上角状态徽章：已连接显示绿色、断开显示红色。通过 keepalive 心跳（每 3 秒 ping + 4 秒超时）结合底层 socket 关闭监听，实时检测断连——主板断电 / WiFi 断开 / frp 隧道断开都能在数秒内感知。

---

## 技术栈

| 组件 | 版本 | 用途 |
|---|---|---|
| Flutter | 3.27 | 跨平台 UI 框架 |
| [dartssh2](https://pub.dev/packages/dartssh2) | 2.11 | 纯 Dart 的 SSH 客户端 |
| [xterm](https://pub.dev/packages/xterm) | 4.0.0（本地 fork） | 终端模拟器（真终端 UI） |
| Material 3 | — | UI 主题 |

> xterm 使用了本地 fork（见 `vendor/xterm`），原因见下文「xterm fork 说明」。

---

## 目录结构

```
lib/
├── main.dart               # 应用入口 → 首页
├── home_screen.dart        # 首页：wifi连接主板 / 远程连接主板 两个按钮
├── auto_login_screen.dart  # WiFi 自动登录页（并发竞速连接两个 IP）
├── login_screen.dart       # WiFi 手动登录（设置）页
├── remote_config_screen.dart  # frp 远程连接配置页
├── control_screen.dart     # 控制台（状态徽章 + 预设指令 + xterm 真终端）
├── ssh_service.dart        # SSH 封装：连接尝试 / 竞速 / keepalive / frp 隧道 / PTY shell
├── commands.dart           # 预设指令定义（WiFi 全量 / 远程精简）
└── network_binding.dart    # Android WiFi 网络绑定（MethodChannel）

android/app/src/main/kotlin/com/example/board_control/MainActivity.kt
                            # Android 原生侧：bindToWifi（bindProcessToNetwork 实现）

vendor/xterm/               # 本地 fork 的 xterm 4.0.0（含软键盘回车修复）
```

---

## 核心设计

### SSH 连接（`ssh_service.dart`）

- **`SshConnectionAttempt`**：一次可取消的 SSH 连接尝试，`cancel()` 会销毁底层 socket 以中断进行中的连接 / 认证。
  - `frpSerial` 非空时走 frp 隧道（先 HTTP CONNECT 握手再 SSH）；
  - 否则直接 TCP 连到 `host:port`（WiFi 直连）。
- **`frpConnect()`**：TCP 连上 frp 服务器后，发送 `CONNECT <序列号> HTTP/1.1` + `Host: <序列号>` 请求，收到 `HTTP/1.1 200` 后把该 socket 包装成 dartssh2 的 `SSHSocket`，SSH 直接跑在隧道上。
- **`raceConnect()`**：并发尝试多个候选，返回最先成功的一个，其余自动取消。
- **`SSHService`**：封装连接、keepalive 探测、断连监听、`openShell`、指令执行；`client` getter 暴露底层 `SSHClient` 供终端组件直接开 shell。

### 断连检测

- `client.done` 捕获正常断开（FIN/RST）；
- 周期 keepalive ping（带超时）捕获静默断开（如 WiFi 突然消失）。
- 通知 listener 的时机放在 `close()` **之前**，避免 `close()` 在底层已出错时抛异常而跳过通知。

### 终端（`control_screen.dart`）

- `Terminal`（xterm）负责解析 ANSI 转义、处理光标 / 回显 / 退格；
- `session.stdout/stderr` 经 UTF-8 解码后喂给 `terminal.write`；
- `terminal.onOutput` 把用户输入写回 `session`，并将软键盘产生的 `\n`（LF）转换为交互式 shell 需要的 `\r`（CR）；
- `terminal.onResize` 同步 `resizeTerminal` 给远端 PTY。

---

## xterm fork 说明

上游 xterm 4.0.0 存在一个移动端软键盘回车失效的 bug：

- 软键盘输入连接实际使用的 `inputAction` 是 `TextInputAction.newline`；
- 但处理回车动作的 `onAction` 回调**只认 `TextInputAction.done`**；
- 结果：中英文输入法（如百度输入法）的回车键触发 `newline` action 时被直接丢弃，表现为「终端里按回车没反应」（字符能正常输入，因为字符走的是文本插入路径，不走 action 路径）。

本地 fork 在 `vendor/xterm/lib/src/terminal_view.dart` 中把 `onAction` 扩展为同时处理 `done` / `newline` / `go` / `send` / `next`，并在 `pubspec.yaml` 通过 `dependency_overrides` 指向 `vendor/xterm`。

```yaml
dependency_overrides:
  xterm:
    path: vendor/xterm
```

**注意**：升级上游 xterm 前需确认该 bug 已修复；若未修复，需把同样的改动重新应用到新版本。

---

## 使用说明

### WiFi 直连

1. 手机连上主板的 WiFi 热点（SSID 如 `LZCZ2024060001T`）。
2. 打开应用 → 点「wifi连接主板」。
3. 自动登录两个候选 IP，先成功者进入控制台；失败可点右上角「设置」手动输入连接信息。
4. 在终端输入命令，回车执行。
5. 点「预设指令」快捷执行 ec20 操作（查看 / 激活 / 中断）。

### 远程连接（frp）

1. 确保主板已通过 frpc 反向注册到 frp 服务器，且手机能访问外网（蜂窝数据或可上网 WiFi）。
2. 打开应用 → 点「远程连接主板」。
3. 确认 / 修改五个字段（服务器地址、代理端口、设备序列号、用户名、密码）。
4. 点「连接」，成功后进入控制台（无 ec20 预设）。

> 远程连接需要手机走能上外网的网络，**不能**连着主板热点（主板热点无外网）。

### 默认连接信息

- 端口：22（WiFi 直连）；frp 代理端口：17011（远程）
- 用户名：root
- 密码：见 `lib/login_screen.dart`、`lib/remote_config_screen.dart` 中的默认值
- WiFi 候选 IP：`192.168.1.1`、`125.126.127.1`
- frp 服务器：`http://concrete-frp.letsgrp.com`

> 默认凭据可在 `lib/auto_login_screen.dart`、`lib/login_screen.dart`、`lib/remote_config_screen.dart` 中修改。如设备对外暴露，请修改默认密码并考虑校验 SSH 主机指纹。

---

## 构建与运行

```bash
flutter pub get
flutter run                    # 连接设备 / 模拟器运行
flutter build apk --debug      # 构建调试 APK
flutter build apk --release    # 构建发布 APK
```

产物位于 `build/app/outputs/flutter-apk/`。

---

## 注意事项

- **Android 模拟器无 WiFi 无线网卡**，WiFi 绑定（`bindProcessToNetwork`）的路径只能在真机上验证；但模拟器可通过主机网络（NAT）访问局域网内主板，用于验证 SSH / 终端流程。
- **主板 AP 无外网**时会被 Android 判定为「无网络」，需要 WiFi 网络绑定（已在 `network_binding.dart` + `MainActivity.kt` 实现）。
- **frp 远程连接**需要手机有外网；连主板热点时无法访问 frp 公网服务器。
- 自动登录的两个候选 IP 对应不同网络位置下的同一类主板（如直连主板热点、或主板接入局域网），可按需增删。
- 若需新增主板或更换 frp 服务器 / 序列号，分别改 `lib/auto_login_screen.dart`、`lib/remote_config_screen.dart` 中的默认值即可。
