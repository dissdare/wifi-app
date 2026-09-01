import 'package:flutter/material.dart';

import 'network_binding.dart';
import 'ssh_service.dart';

/// 手动连接（设置）页：可输入主板 IP / 端口 / 用户名 / 密码主动连接。
class LoginScreen extends StatefulWidget {
  /// 点击「连接」时触发，用于让后台自动登录尝试退出。
  final VoidCallback? onManualConnect;

  /// 手动连接成功时触发，传入已连接的服务。
  final void Function(SSHService service)? onConnected;

  const LoginScreen({super.key, this.onManualConnect, this.onConnected});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 主板固定 IP 与默认账号，可直接改这里作为默认值。
  final _hostCtrl = TextEditingController(text: '125.126.127.1');
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController(text: 'root');
  final _passCtrl = TextEditingController(text: 'Lets@002398');

  final _service = SSHService();
  bool _connecting = false;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    // 主动连接时，让后台为两个 IP 进行的自动登录尝试退出。
    widget.onManualConnect?.call();

    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 22;
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;

    if (host.isEmpty || user.isEmpty) {
      _showMessage('请填写主机地址和用户名');
      return;
    }

    setState(() => _connecting = true);
    try {
      // 先尝试把流量绑定到 WiFi，避免被蜂窝数据抢走（主板热点无外网）。
      await bindProcessToWifi();
      await _service.connect(
        host: host,
        port: port,
        username: user,
        password: pass,
      );
      if (!mounted) return;
      debugPrint('[board_control] SSH 登录成功: $host:$port');
      widget.onConnected?.call(_service);
    } catch (e) {
      debugPrint('[board_control] SSH 登录失败: $e');
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
      appBar: AppBar(title: const Text('连接设置')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.router, size: 64, color: Colors.teal),
                const SizedBox(height: 8),
                Text(
                  '连接主板',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text(
                  '手机需先连接到主板的热点 WiFi',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _hostCtrl,
                  decoration: const InputDecoration(
                    labelText: '主机 IP',
                    hintText: '如 192.168.4.1',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _portCtrl,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                  keyboardType: TextInputType.number,
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
