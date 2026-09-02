import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'commands.dart';
import 'ssh_service.dart';
import 'tunnel.dart';
import 'tunnel_sheet.dart';

class ControlScreen extends StatefulWidget {
  final SSHService service;

  /// 控制页顶部展示的预设指令列表；默认用全部预设（含 ec20）。
  /// 远程连接时传入 [remotePresetCommands]（为空，不显示预设面板）。
  final List<CommandDef> presets;

  const ControlScreen({
    super.key,
    required this.service,
    this.presets = presetCommands,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  /// 真正的终端模拟器：解析 ANSI 转义、处理光标、回显、退格、tab 补全等。
  final terminal = Terminal(maxLines: 10000);

  SSHSession? _session;
  bool _connected = true;

  /// 当前运行的本地转发隧道；null 表示未建立。
  LocalTunnel? _tunnel;

  /// resize 去抖定时器：键盘弹出/收起动画期间尺寸连续变化，
  /// 只在稳定后真正通知远端 PTY，避免反复 SIGWINCH 重绘导致抖动。
  Timer? _resizeTimer;

  /// 粘滞修饰键状态：点一次 CTRL/ALT 进入激活态（高亮），
  /// 下一个按键组合后自动释放（与 Termux 行为一致）。
  bool _ctrlActive = false;
  bool _altActive = false;

  @override
  void initState() {
    super.initState();
    _initTerminal();
  }

  /// 打开交互式 shell，并把终端与 shell 双向绑定。
  Future<void> _initTerminal() async {
    try {
      final client = widget.service.client;
      if (client == null) {
        throw StateError('尚未连接');
      }

      final session = await client.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );
      if (!mounted) {
        session.close();
        return;
      }
      _session = session;

      // 终端尺寸变化 → 通知远端 PTY 调整行列数。
      // 键盘弹出/收起是渐进动画，尺寸连续变化；每次变化都 resize 会反复
      // 触发远端 shell 的 SIGWINCH 重绘。这里做去抖，只在尺寸稳定后再通知。
      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        _resizeTimer?.cancel();
        _resizeTimer = Timer(const Duration(milliseconds: 150), () {
          session.resizeTerminal(width, height, pixelWidth, pixelHeight);
        });
      };

      // 用户在软键盘敲普通字符 → 应用粘滞修饰键 → 写回 shell。
      // 软键盘回车键产生 \n（LF），交互式 shell 需要 \r（CR），统一转换。
      terminal.onOutput = (data) {
        var out = data.replaceAll('\n', '\r');
        if (_ctrlActive) {
          out = _applyCtrl(out);
        }
        if (_altActive) {
          out = '\x1b$out';
        }
        if (_ctrlActive || _altActive) {
          setState(() {
            _ctrlActive = false;
            _altActive = false;
          });
        }
        session.write(utf8.encode(out));
      };

      // shell 的 stdout / stderr → 喂给终端渲染。
      session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(terminal.write);
      session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(terminal.write);

      // 监听连接断开（主板断电 / WiFi 断开）→ 状态变红色。
      widget.service.addDisconnectListener(_onDisconnected);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connected = false;
      });
      terminal.write('\r\n无法打开终端：$e\r\n');
    }
  }

  void _onDisconnected() {
    // 连接断开时同步清理隧道，让按钮回到灰色。
    final tunnel = _tunnel;
    _tunnel = null;
    tunnel?.stop();
    if (mounted) setState(() => _connected = false);
  }

  /// 对普通字符应用 Ctrl 组合（参照 VT 控制字符映射）：
  /// a-z → 0x01-0x1a，A-Z → 0x01-0x1a，[ \ ] ^ _ → 0x1b-0x1f，空格 → 0x00。
  String _applyCtrl(String s) {
    final sb = StringBuffer();
    for (final ch in s.split('')) {
      final code = ch.codeUnitAt(0);
      if (code >= 0x61 && code <= 0x7a) {
        sb.writeCharCode(code - 0x60); // a-z → 1-26
      } else if (code >= 0x41 && code <= 0x5a) {
        sb.writeCharCode(code - 0x40); // A-Z → 1-26
      } else if (code >= 0x5b && code <= 0x5f) {
        sb.writeCharCode(code - 0x5b + 27); // [ \ ] ^ _ → 27-31
      } else if (code == 0x20) {
        sb.writeCharCode(0); // 空格 → 0
      } else {
        sb.write(ch);
      }
    }
    return sb.toString();
  }

  /// 释放粘滞修饰键并刷新高亮状态。
  void _releaseModifiers() {
    if (_ctrlActive || _altActive) {
      setState(() {
        _ctrlActive = false;
        _altActive = false;
      });
    }
  }

  /// 特殊按键条上的一个「立即发送」键：按下即发送对应字节序列，
  /// 并把当前粘滞的 ctrl/alt 一并应用（如 ctrl+方向键 → 跳词）。
  void _pressSpecialKey(String Function(bool ctrl, bool alt) buildSeq) {
    final ctrl = _ctrlActive;
    final alt = _altActive;
    _releaseModifiers();
    final seq = buildSeq(ctrl, alt);
    _session?.write(utf8.encode(seq));
  }

  /// 发送方向键；带 ctrl 时生成 \x1b[1;5X（跳词），带 alt 时 \x1b[1;3X。
  void _pressArrow(String baseCode) {
    _pressSpecialKey((ctrl, alt) {
      if (ctrl) return '\x1b[1;5$baseCode';
      if (alt) return '\x1b[1;3$baseCode';
      return '\x1b[$baseCode';
    });
  }

  /// 执行预设指令（普通命令写入 shell）。
  void _sendPreset(CommandDef cmd) {
    final session = _session;
    if (session == null) return;
    session.write(utf8.encode('${cmd.command}\n'));
  }

  @override
  void dispose() {
    _resizeTimer?.cancel();
    widget.service.removeDisconnectListener(_onDisconnected);
    _session?.close();
    _tunnel?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('主板控制台'),
        actions: [
          _buildTunnelButton(),
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 4),
            child: Center(child: _buildStatusBadge()),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.presets.isNotEmpty) ...[
            _buildPresetPanel(),
            const Divider(height: 1),
          ],
          Expanded(
            child: TerminalView(
              terminal,
              autofocus: true,
              // 默认是 emailAddress 键盘，回车键不产生换行；改成 text。
              keyboardType: TextInputType.text,
              padding: const EdgeInsets.all(8),
              textStyle: const TerminalStyle(fontSize: 14, height: 1.3),
            ),
          ),
          _buildKeyBar(),
        ],
      ),
    );
  }

  /// 隧道按钮：与右侧连接状态徽章同款样式（浅色圆角底 + 彩色文字）。
  /// 连接成功绿色，未连接灰色。
  Widget _buildTunnelButton() {
    final running = _tunnel != null && _tunnel!.isRunning;
    final color = running ? Colors.green : Colors.grey;
    final bg =
        running ? const Color(0xFFE8F5E9) : const Color(0xFFF2F2F2);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _openTunnelSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '隧道',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 弹出隧道配置框。
  Future<void> _openTunnelSheet() async {
    final client = widget.service.client;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TunnelSheet(
        client: client,
        currentTunnel: _tunnel,
        onTunnelChanged: (tunnel) {
          if (mounted) setState(() => _tunnel = tunnel);
        },
      ),
    );
  }

  /// 右上角连接状态标志：已连接浅绿 / 已断开红色。
  Widget _buildStatusBadge() {
    final color = _connected ? Colors.green : Colors.red;
    final bg =
        _connected ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            _connected ? '已连接' : '已断开',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部预设指令面板（WiFi 有 ec20 预设，远程无）。
  Widget _buildPresetPanel() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('预设指令', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cmd in widget.presets)
                ActionChip(
                  label: Text(cmd.label),
                  onPressed: () => _sendPreset(cmd),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 底部特殊按键条（仿 Termux extra keys）：
  /// ESC、TAB、CTRL、ALT、←、→、↑、↓。
  Widget _buildKeyBar() {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _keyButton('ESC', () {
              _pressSpecialKey((_, alt) => alt ? '\x1b\x1b' : '\x1b');
            }),
            _keyButton('TAB', () {
              _pressSpecialKey((_, __) => '\x09');
            }),
            _modifierKey('CTRL', _ctrlActive, () {
              setState(() => _ctrlActive = !_ctrlActive);
            }),
            _modifierKey('ALT', _altActive, () {
              setState(() => _altActive = !_altActive);
            }),
            _keyButton('←', () => _pressArrow('D')),
            _keyButton('→', () => _pressArrow('C')),
            _keyButton('↑', () => _pressArrow('A')),
            _keyButton('↓', () => _pressArrow('B')),
          ],
        ),
      ),
    );
  }

  /// 普通功能键按钮。
  Widget _keyButton(String label, VoidCallback onTap) {
    return _buildKeyButton(label, onTap, active: false);
  }

  /// 修饰键按钮（CTRL/ALT），激活时高亮。
  Widget _modifierKey(String label, bool active, VoidCallback onTap) {
    return _buildKeyButton(label, onTap, active: active);
  }

  /// 单个按键：用 GestureDetector（不抢焦点，软键盘保持打开），
  /// 按下即触发（onTapDown），响应更接近真实键盘。
  Widget _buildKeyButton(String label, VoidCallback onTap,
      {required bool active}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => onTap(),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF3D6DEB) : const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
