# 主板控制台 (Board Control)

通过 **WiFi 局域网直连** 或 **frp 内网穿透** 远程控制嵌入式 Linux 主板的 Flutter 应用。

手机打开应用后提供两种连接方式：连接主板自带 WiFi 热点走局域网 SSH，或通过 frp 服务器从任意网络（蜂窝 / 外网）反向穿透到主板。连接成功后进入一个 **真正的交互式终端**（基于 PTY + xterm 终端模拟器），可直接输入命令、`cd` 切换目录，带一键预设指令（查询 / 激活 4G 模块 ec20）、仿 Termux 的特殊按键条、实时连接状态指示，以及把主板局域网流量转发到手机本地访问的 **隧道（端口转发）** 功能。

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
| 密码 | （见源码默认值） | 目标主板的 SSH 密码（掩码显示） |

**序列号记忆**：远程连接成功后，设备序列号会持久化到本地（SharedPreferences），下次打开远程配置页时自动回填，方便快速重连同一台设备。

**网络切换恢复**：远程连接前会先解除进程网络绑定（`bindProcessToNetwork(null)`），让 socket 走系统默认网络。避免「先 WiFi 直连绑定到无外网热点 → 切回可上网网络后远程连不上」的问题（此前只有重启 App 才能恢复）。

连接成功后进入与 WiFi 相同的控制台页面，但**不显示** ec20 预设按钮。

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

### 底部特殊按键条（仿 Termux）

终端下方有一排手机软键盘没有的特殊按键：

- **ESC / TAB**：直接发送对应控制字符；
- **CTRL / ALT**：粘滞修饰键，点亮后按下一个键即组合（如 `CTRL` + `C` 发送中断信号），组合后自动熄灭；
- **← / → / ↑ / ↓**：方向键；配合 CTRL / ALT 可发送跳词（`\x1b[1;5D`）等组合序列。

软键盘回车键产生的 `\n`（LF）会统一转换为交互式 shell 需要的 `\r`（CR）。

### 预设指令

顶部「预设指令」面板（`ActionChip` 按钮）：

- **查看 ec20 激活状态**：查询主板 4G 模块 usbnet 激活状态
- **激活 ec20**：下发 AT 命令激活 ec20

返回结果前后各空一行，更醒目。中断操作由底部 `CTRL` + `C` 组合键承担，不再单独设按钮。

> WiFi 连接显示预设面板；远程连接不显示（远程页面无 ec20 操作）。

### 隧道（SSH 端口转发）

远程连接控制页右上角有「隧道」按钮，用于把主板局域网内的设备流量通过 SSH 转发到手机本地，让手机浏览器直接访问主板所连局域网里的设备（类似 WindTerm / `ssh -L` 本地端口转发）。

数据链路：

```
手机浏览器 → http://127.0.0.1:本地端口 → frp → 主板(SSH) → 局域网设备(目标IP:目标端口)
```

- **配置项**：目标 IP（默认 `192.168.20.61`）、目标端口（默认 `80`）、本地端口（默认 `33876`）。
- **连通性校验**：建立隧道前会先通过 SSH 让主板去连一次目标，**只有主板真能连上目标才建立隧道**。目标 IP 不存在或端口不通时直接报「隧道建立失败」。这比 ping 更严格——ping 通但端口没开时隧道照样连不上。
- **本地网址**：连接成功后配置框里显示「查看网址」，如 `http://127.0.0.1:33876`（端口跟随本地端口），可一键复制到浏览器访问。
- **状态指示**：隧道按钮与右侧连接状态徽章同款样式，未连接灰色、连接成功绿色。
- **心跳保活**：运行期间每 3 秒探测一次目标可达性，目标设备断线累计 5 秒后隧道自动断开并回到灰色。

> 目标 IP 是**主板视角**的局域网地址（SSH 服务器负责去连接它），不是手机的地址。

### 连接状态指示

右上角状态徽章：已连接显示绿色、断开显示红色。

### 连接稳定性

针对「偶尔网络波动就断开」的问题，SSH 连接和隧道都采用 **5 秒宽限** 策略：

- **SSH keepalive**：每 2 秒 ping 一次（超时 2 秒）。单次失败不立即断开，只记录首次失败时间；期间任一 ping 成功即清零失败累计；从首次失败起累计满 5 秒仍无一次成功，才判定真正断开。短暂丢包 / 网络切换不会误断。
- **隧道心跳**：每 3 秒探测一次目标，逻辑同上（累计 5 秒失败才断开）。

底层 socket 正常关闭（FIN/RST）仍通过 `client.done` 监听立即感知。

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
├── remote_config_screen.dart  # frp 远程连接配置页（含序列号记忆）
├── control_screen.dart     # 控制台（状态徽章 + 隧道按钮 + 预设指令 + 特殊按键条 + xterm 真终端）
├── ssh_service.dart        # SSH 封装：连接尝试 / 竞速 / keepalive / frp 隧道 / PTY shell
├── tunnel.dart             # 本地端口转发引擎（SSH -L 实现 + 心跳探测）
├── tunnel_sheet.dart       # 隧道配置弹层（目标IP/端口/本地端口 + 网址展示）
├── commands.dart           # 预设指令定义（ec20 查询/激活）
└── network_binding.dart    # Android 网络绑定/解绑 + 序列号持久化（MethodChannel）

android/app/src/main/kotlin/com/example/board_control/MainActivity.kt
                            # Android 原生侧：bindToWifi / unbindProcessNetwork /
                            #   saveSerial / getSerial（SharedPreferences）

vendor/xterm/               # 本地 fork 的 xterm 4.0.0（含软键盘回车 + 滚动对齐修复）
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

### 断连检测与稳定性

- `client.done` 捕获正常断开（FIN/RST）；
- 周期 keepalive ping（带超时）捕获静默断开（如 WiFi 突然消失），并采用 5 秒宽限策略避免误断（见上文「连接稳定性」）。
- 通知 listener 的时机放在 `close()` **之前**，避免 `close()` 在底层已出错时抛异常而跳过通知。

### 隧道（`tunnel.dart`）

- **`LocalTunnel`**：一条本地端口转发隧道。`start()` 先用 `forwardLocal` 探测目标连通性（失败即抛异常不建立），再 `ServerSocket.bind(127.0.0.1:本地端口)` 监听；每个进来的本地连接建一条 `direct-tcpip` 通道，与本地 socket 双向 pipe。
- **`_ForwardedConn`**：单条转发连接的双向管道，任一端关闭即清理另一端。
- **心跳**：运行期间周期性探测目标，连续失败满 5 秒自动 `stop()` 并回调 `onClosed` 通知 UI。

### 终端（`control_screen.dart`）

- `Terminal`（xterm）负责解析 ANSI 转义、处理光标 / 回显 / 退格；
- `session.stdout/stderr` 经 UTF-8 解码后喂给 `terminal.write`；
- `terminal.onOutput` 把用户输入写回 `session`，并将软键盘产生的 `\n`（LF）转换为交互式 shell 需要的 `\r`（CR），同时应用粘滞的 CTRL / ALT 修饰；
- `terminal.onResize` 同步 `resizeTerminal` 给远端 PTY（150ms 去抖，避免键盘动画期间反复 SIGWINCH 重绘）。

### 键盘动画滚动对齐（`vendor/xterm`）

软键盘弹出 / 收起是渐进动画，视口高度连续变化会产生亚像素的滚动偏移，paint 时 `truncateToDouble` 截断导致整屏字体 1px 跳动。修复方案：让 `_scrollOffset` 和 `_maxScrollExtent` 都对齐到 cellHeight 整数倍，视口高度也向下对齐到整数行，保证贴底时光标行完整绘制、每行都画在精确的整数像素行上。

---

## xterm fork 说明

上游 xterm 4.0.0 存在两个问题，本地 fork 在 `vendor/xterm` 中修复：

### 1. 移动端软键盘回车失效

- 软键盘输入连接实际使用的 `inputAction` 是 `TextInputAction.newline`；
- 但处理回车动作的 `onAction` 回调**只认 `TextInputAction.done`**；
- 结果：中英文输入法（如百度输入法）的回车键触发 `newline` action 时被直接丢弃，表现为「终端里按回车没反应」（字符能正常输入，因为字符走的是文本插入路径，不走 action 路径）。

修复：`vendor/xterm/lib/src/terminal_view.dart` 把 `onAction` 扩展为同时处理 `done` / `newline` / `go` / `send` / `next`。

### 2. 键盘弹出/收起时字体抖动

修复见上文「键盘动画滚动对齐」，改动在 `vendor/xterm/lib/src/ui/render.dart`。

`pubspec.yaml` 通过 `dependency_overrides` 指向本地 fork：

```yaml
dependency_overrides:
  xterm:
    path: vendor/xterm
```

**注意**：升级上游 xterm 前需确认上述问题已修复；若未修复，需把同样的改动重新应用到新版本。

---

## 使用说明

### WiFi 直连

1. 手机连上主板的 WiFi 热点（SSID 如 `LZCZ2024060001T`）。
2. 打开应用 → 点「wifi连接主板」。
3. 自动登录两个候选 IP，先成功者进入控制台；失败可点右上角「设置」手动输入连接信息。
4. 在终端输入命令，回车执行。
5. 点「预设指令」快捷执行 ec20 操作（查看 / 激活），中断用底部 `CTRL` + `C`。

### 远程连接（frp）

1. 确保主板已通过 frpc 反向注册到 frp 服务器，且手机能访问外网（蜂窝数据或可上网 WiFi）。
2. 打开应用 → 点「远程连接主板」。
3. 确认 / 修改五个字段（服务器地址、代理端口、设备序列号、用户名、密码）。
4. 点「连接」，成功后进入控制台（无 ec20 预设）。

> 远程连接需要手机走能上外网的网络，**不能**连着主板热点（主板热点无外网）。若之前 WiFi 直连绑定过主板热点、之后切回可上网网络连不上，应用已自动解绑，无需重启。

### 使用隧道访问局域网设备

1. 远程连接成功后，点右上角「隧道」按钮。
2. 填写目标 IP（主板局域网内设备地址，默认 `192.168.20.61`）、目标端口（默认 `80`）、本地端口（默认 `33876`）。
3. 点「连接」。若主板连不上该目标会提示失败；成功后按钮变绿，显示「查看网址」。
4. 复制网址（如 `http://127.0.0.1:33876`）到手机浏览器访问，即访问目标设备。

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
- 隧道目标 IP 填主板局域网内可访问的地址，本地端口若被占用需换一个。
