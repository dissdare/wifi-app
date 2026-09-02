import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tunnel.dart';

/// 隧道配置底部弹层：配置目标 IP/端口、本地端口，建立或断开本地转发，
/// 连接成功后展示可在浏览器访问的本地网址。
class TunnelSheet extends StatefulWidget {
  /// 已认证的 SSH 客户端（远程连接成功后非空）。
  final SSHClient? client;

  /// 当前正在运行的隧道（用于回填和展示状态）；无则为 null。
  final LocalTunnel? currentTunnel;

  /// 隧道状态变化回调：新建/销毁隧道时通知父组件刷新按钮颜色。
  final ValueChanged<LocalTunnel?> onTunnelChanged;

  const TunnelSheet({
    super.key,
    required this.client,
    required this.currentTunnel,
    required this.onTunnelChanged,
  });

  @override
  State<TunnelSheet> createState() => _TunnelSheetState();
}

class _TunnelSheetState extends State<TunnelSheet> {
  late final TextEditingController _targetIpCtrl;
  late final TextEditingController _targetPortCtrl;
  late final TextEditingController _localPortCtrl;

  LocalTunnel? _tunnel;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.currentTunnel;
    _tunnel = (t != null && t.isRunning) ? t : null;
    _targetIpCtrl = TextEditingController(
      text: _tunnel?.remoteHost ?? '192.168.20.61',
    );
    _targetPortCtrl = TextEditingController(
      text: (_tunnel?.remotePort ?? 80).toString(),
    );
    _localPortCtrl = TextEditingController(
      text: (_tunnel?.localPort ?? 33876).toString(),
    );
  }

  @override
  void dispose() {
    _targetIpCtrl.dispose();
    _targetPortCtrl.dispose();
    _localPortCtrl.dispose();
    super.dispose();
  }

  bool get _running => _tunnel != null && _tunnel!.isRunning;

  Future<void> _toggle() async {
    if (_busy) return;
    if (_running) {
      await _disconnect();
    } else {
      await _connect();
    }
  }

  Future<void> _connect() async {
    final client = widget.client;
    if (client == null) {
      setState(() => _error = '尚未连接，无法建立隧道');
      return;
    }
    final ip = _targetIpCtrl.text.trim();
    final targetPort = int.tryParse(_targetPortCtrl.text.trim());
    final localPort = int.tryParse(_localPortCtrl.text.trim());
    if (ip.isEmpty || targetPort == null || localPort == null) {
      setState(() => _error = '请填写有效的目标 IP 和端口');
      return;
    }
    if (targetPort < 1 || targetPort > 65535 || localPort < 1 || localPort > 65535) {
      setState(() => _error = '端口需在 1~65535 之间');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tunnel = LocalTunnel(
        client: client,
        remoteHost: ip,
        remotePort: targetPort,
        localPort: localPort,
      );
      // 隧道因目标不可达而自动断开时，同步通知父组件刷新按钮颜色。
      final notify = widget.onTunnelChanged;
      tunnel.onClosed = () {
        notify(null);
        if (mounted) setState(() => _tunnel = null);
      };
      await tunnel.start();
      if (!mounted) {
        await tunnel.stop();
        return;
      }
      setState(() => _tunnel = tunnel);
      widget.onTunnelChanged(tunnel);
    } catch (e) {
      if (mounted) setState(() => _error = '隧道建立失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final tunnel = _tunnel;
    if (tunnel == null) return;
    setState(() => _busy = true);
    await tunnel.stop();
    if (!mounted) return;
    setState(() {
      _tunnel = null;
      _busy = false;
    });
    widget.onTunnelChanged(null);
  }

  Future<void> _copyUrl() async {
    final tunnel = _tunnel;
    if (tunnel == null) return;
    await Clipboard.setData(ClipboardData(text: tunnel.localUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网址已复制到剪贴板'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '隧道配置',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _targetIpCtrl,
              decoration: const InputDecoration(
                labelText: '目标IP',
                hintText: '主板局域网内的设备 IP',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lan_outlined),
              ),
              keyboardType: TextInputType.number,
              enabled: !_running,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetPortCtrl,
              decoration: const InputDecoration(
                labelText: '目标端口',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.settings_ethernet),
              ),
              keyboardType: TextInputType.number,
              enabled: !_running,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _localPortCtrl,
              decoration: const InputDecoration(
                labelText: '本地端口',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phonelink),
              ),
              keyboardType: TextInputType.number,
              enabled: !_running,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _toggle,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: _running ? Colors.red : null,
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_running ? '断开隧道' : '连接'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
            if (_running) ...[
              const SizedBox(height: 20),
              const Text(
                '查看网址',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _tunnel!.localUrl,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制网址',
                    icon: const Icon(Icons.copy),
                    onPressed: _copyUrl,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
