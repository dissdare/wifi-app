import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'commands.dart';
import 'ssh_service.dart';

class ControlScreen extends StatefulWidget {
  final SSHService service;

  /// 控制页顶部展示的预设指令列表；默认用全部预设（含 ec20）。
  /// 远程连接时传入 [remotePresetCommands]，去掉 ec20 相关按钮。
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
      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        session.resizeTerminal(width, height, pixelWidth, pixelHeight);
      };

      // 用户在终端敲键盘 → 原始字节写回 shell。
      // 软键盘的回车键产生的是 \n（LF），但交互式 shell 需要 \r（CR），
      // 这里统一转换，否则命令不会执行。
      terminal.onOutput = (data) {
        // 诊断：记录含控制字符的输入，便于定位软键盘回车路径。
        final codes = data.codeUnits
            .map((c) => c < 32 ? '\\x${c.toRadixString(16)}' : String.fromCharCode(c))
            .join('');
        debugPrint('[board_control] onOutput: "$codes"');
        session.write(utf8.encode(data.replaceAll('\n', '\r')));
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
    if (mounted) setState(() => _connected = false);
  }

  /// 执行预设指令：普通命令写入 shell，中断指令发送 Ctrl+C。
  void _sendPreset(CommandDef cmd) {
    final session = _session;
    if (session == null) return;
    if (cmd.interrupt) {
      session.write(Uint8List.fromList(const [0x03]));
    } else {
      session.write(utf8.encode('${cmd.command}\n'));
    }
  }

  @override
  void dispose() {
    widget.service.removeDisconnectListener(_onDisconnected);
    _session?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.service.host == null
              ? '主板控制台'
              : '主板控制台 · ${widget.service.host}',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: _buildStatusBadge()),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPresetPanel(),
          const Divider(height: 1),
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
        ],
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

  /// 顶部预设指令面板（保持原来的 ActionChip 样式）。
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
                  avatar: cmd.interrupt
                      ? const Icon(Icons.stop_circle_outlined, size: 18)
                      : null,
                  onPressed: () => _sendPreset(cmd),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
