import 'package:flutter/material.dart';

import 'commands.dart';
import 'control_screen.dart';
import 'ssh_service.dart';

/// 远程连接（frp 隧道）配置页。
///
/// 通过 frp 服务器把 SSH 流量转发到设备。SSH 用户名携带设备序列号，
/// frp 服务器据此路由到对应设备。连接成功后进入控制页（无 ec20 预设）。
class RemoteConfigScreen extends StatefulWidget {
  const RemoteConfigScreen({super.key});

  @override
  State<RemoteConfigScreen> createState() => _RemoteConfigScreenState();
}

class _RemoteConfigScreenState extends State<RemoteConfigScreen> {
  final _frpAddrCtrl =
      TextEditingController(text: 'http://concrete-frp.letsgrp.com');
  final _frpPortCtrl = TextEditingController(text: '17011');
  final _serialCtrl = TextEditingController(text: 'LZCZ2025080001');
  final _userCtrl = TextEditingController(text: 'root');
  final _passCtrl = TextEditingController(text: 'Lets@002398');

  final _service = SSHService();
  bool _connecting = false;

  @override
  void dispose() {
    _frpAddrCtrl.dispose();
    _frpPortCtrl.dispose();
    _serialCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// 从地址里剥离 scheme（http:// / https://）和路径，只保留主机名。
  /// 端口由单独的「frp代理端口」字段提供，不从这里解析。
  String _extractHost(String address) {
    var host = address.trim();
    if (host.startsWith('http://')) {
      host = host.substring('http://'.length);
    } else if (host.startsWith('https://')) {
      host = host.substring('https://'.length);
    }
    host = host.split('/').first;
    host = host.split(':').first;
    return host;
  }

  Future<void> _connect() async {
    final host = _extractHost(_frpAddrCtrl.text);
    final port = int.tryParse(_frpPortCtrl.text.trim()) ?? 17011;
    final serial = _serialCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;

    if (host.isEmpty || serial.isEmpty || user.isEmpty) {
      _showMessage('请填写服务器地址、设备序列号和用户名');
      return;
    }

    // SSH 用户名携带设备序列号，frp 服务器据此路由到对应设备。
    // 若服务器要求「序列号@用户名」，把下面两段顺序对调即可。
    final sshUsername = '$user@$serial';

    setState(() => _connecting = true);
    try {
      await _service.connect(
        host: host,
        port: port,
        username: sshUsername,
        password: pass,
      );
      if (!mounted) return;
      debugPrint('[board_control] frp 连接成功: $host:$port ($sshUsername)');
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ControlScreen(
            service: _service,
            presets: remotePresetCommands,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[board_control] frp 连接失败: $e');
      if (mounted) _showMessage('连接失败：$e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('远程连接配置')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.cloud_outlined, size: 64, color: Colors.teal),
                const SizedBox(height: 8),
                Text(
                  '远程连接主板',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _frpAddrCtrl,
                  decoration: const InputDecoration(
                    labelText: 'frp服务器地址',
                    hintText: '如 http://concrete-frp.letsgrp.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _frpPortCtrl,
                  decoration: const InputDecoration(
                    labelText: 'frp代理端口',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _serialCtrl,
                  decoration: const InputDecoration(
                    labelText: '设备序列号',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _connecting ? null : _connect,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _connecting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('连接'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
