import 'package:flutter/material.dart';

import 'control_screen.dart';
import 'login_screen.dart';
import 'network_binding.dart';
import 'ssh_service.dart';

/// 自动登录候选 IP。端口/账号/密码与手动登录默认值一致。
const _autoTargets = ['192.168.1.1', '125.126.127.1'];
const _autoPort = 22;
const _autoUsername = 'root';
const _autoPassword = 'Lets@002398';

enum _Phase { connecting, failed, disconnected }

/// 启动页：进入即并发尝试两个 IP 自动登录，先成功者进入控制页，
/// 另一个尝试被取消。右上角提供设置按钮进入手动连接页。
class AutoLoginScreen extends StatefulWidget {
  /// 进入时是否自动尝试连接（测试时传 false 跳过网络）。
  final bool autoConnect;

  const AutoLoginScreen({super.key, this.autoConnect = true});

  @override
  State<AutoLoginScreen> createState() => _AutoLoginScreenState();
}

class _AutoLoginScreenState extends State<AutoLoginScreen> {
  final List<SshConnectionAttempt> _attempts = [];
  final Map<String, String> _status = {};
  _Phase _phase = _Phase.connecting;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    for (final host in _autoTargets) {
      _status[host] = '连接中…';
    }
    if (widget.autoConnect) {
      _startAutoLogin();
    } else {
      _phase = _Phase.disconnected;
    }
  }

  Future<void> _startAutoLogin() async {
    // 无外网热点场景：先把进程流量绑定到 WiFi，避免被蜂窝数据抢走。
    await bindProcessToWifi();

    if (!mounted) return;

    for (final host in _autoTargets) {
      _attempts.add(SshConnectionAttempt(
        host: host,
        port: _autoPort,
        username: _autoUsername,
        password: _autoPassword,
      ));
    }

    try {
      final result = await raceConnect(_attempts);
      if (!mounted) return;
      await _onSuccess(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        for (final host in _autoTargets) {
          _status[host] = '连接失败';
        }
      });
    }
  }

  Future<void> _onSuccess(ConnectResult result) async {
    if (_navigated) {
      result.client.close();
      return;
    }
    final service = SSHService()..adopt(result.client, host: result.host);
    await _goControl(service);
  }

  /// 进入控制页；断开返回后停在「已断开」状态，不自动重连。
  Future<void> _goControl(SSHService service) async {
    if (_navigated) {
      service.disconnect();
      return;
    }
    _navigated = true;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => ControlScreen(service: service)),
      (route) => route.isFirst,
    );
    if (!mounted) return;
    _navigated = false;
    setState(() => _phase = _Phase.disconnected);
  }

  void _cancelAutoLogin() {
    for (final a in _attempts) {
      a.cancel();
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          onManualConnect: _cancelAutoLogin,
          onConnected: (service) => _goControl(service),
        ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _phase = _Phase.connecting;
      _attempts.clear();
      for (final host in _autoTargets) {
        _status[host] = '连接中…';
      }
    });
    _startAutoLogin();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('主板控制台'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_phase == _Phase.connecting)
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(strokeWidth: 4),
                )
              else if (_phase == _Phase.failed)
                const Icon(Icons.error_outline, size: 64, color: Colors.grey)
              else
                const Icon(Icons.link_off, size: 64, color: Colors.grey),
              const SizedBox(height: 24),
              Text(
                switch (_phase) {
                  _Phase.connecting => '正在自动连接主板…',
                  _Phase.failed => '自动连接失败',
                  _Phase.disconnected => '已断开连接',
                },
                style: const TextStyle(fontSize: 16),
              ),
              if (_phase == _Phase.failed) ...[
                const SizedBox(height: 8),
                const Text(
                  '请点击右上角设置，手动输入连接信息',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
              const SizedBox(height: 24),
              if (_phase != _Phase.disconnected)
                for (final host in _autoTargets)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '$host  ·  ${_status[host] ?? ''}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              const SizedBox(height: 24),
              if (_phase != _Phase.connecting)
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新连接'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
