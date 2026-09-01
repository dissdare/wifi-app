import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import 'commands.dart';
import 'ssh_service.dart';

/// ANSI 转义序列（颜色/控制码），终端输出中过滤掉，只保留纯文本。
final _ansiEscape = RegExp(
  r'\x1B(?:\[[0-9;?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)|[@-Z\\-_])',
);

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
  SSHSession? _shell;
  final _inputCtrl = TextEditingController();
  final _scroll = ScrollController();
  String _output = '';
  bool _connected = true;

  @override
  void initState() {
    super.initState();
    _initTerminal();
  }

  /// 打开交互式 shell 并监听输出 / 连接断开。
  Future<void> _initTerminal() async {
    try {
      final shell = await widget.service.openShell();
      if (!mounted) {
        shell.close();
        return;
      }
      _shell = shell;
      // 用 stateful 的 utf8.decoder 跨 chunk 正确解码中文等多字节字符。
      utf8.decoder.bind(shell.stdout).listen(_onText);
      utf8.decoder.bind(shell.stderr).listen(_onText);

      // 监听连接断开（主板断电 / WiFi 断开）→ 状态变红色。
      widget.service.addDisconnectListener(_onDisconnected);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _output = '无法打开终端：$e\n';
      });
    }
  }

  void _onDisconnected() {
    if (mounted) setState(() => _connected = false);
  }

  void _onText(String text) {
    // 去掉 ANSI 转义序列（颜色码等），只保留纯文本。
    text = text.replaceAll(_ansiEscape, '');
    // 规范化换行，避免 CR（\r）导致的显示异常。
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (!mounted) return;
    setState(() => _output += text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// 发送用户在终端输入的命令。
  void _sendCommand(String raw) {
    if (raw.isEmpty) return;
    _shell?.write(utf8.encode('$raw\n'));
    _inputCtrl.clear();
  }

  /// 执行预设指令：普通命令写入 shell，中断指令发送 Ctrl+C。
  void _sendPreset(CommandDef cmd) {
    if (cmd.interrupt) {
      _shell?.write(Uint8List.fromList(const [0x03]));
    } else {
      _shell?.write(utf8.encode('${cmd.command}\n'));
    }
  }

  @override
  void dispose() {
    widget.service.removeDisconnectListener(_onDisconnected);
    _shell?.close();
    _inputCtrl.dispose();
    _scroll.dispose();
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
          Expanded(child: _buildTerminal()),
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

  /// 终端区域：实时输出 + 底部输入框，像 SSH 登录后的终端。
  Widget _buildTerminal() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF121212),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: SelectableText(
                  _output.isEmpty ? '正在连接终端…' : _output,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
          _buildTerminalInput(),
        ],
      ),
    );
  }

  Widget _buildTerminalInput() {
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          const Text(
            r'$ ',
            style: TextStyle(
              color: Colors.greenAccent,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                hintText: '输入命令，回车执行',
                border: InputBorder.none,
                isDense: true,
                hintStyle: TextStyle(color: Colors.white38),
              ),
              onSubmitted: _sendCommand,
            ),
          ),
        ],
      ),
    );
  }
}
