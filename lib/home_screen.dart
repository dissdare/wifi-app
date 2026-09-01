import 'package:flutter/material.dart';

import 'auto_login_screen.dart';
import 'remote_config_screen.dart';

/// 首页：选择连接方式——本地 WiFi 直连 或 远程 frp 连接。
class HomeScreen extends StatelessWidget {
  /// 点击「wifi连接主板」进入自动登录页后，是否自动尝试连接。
  final bool autoConnect;

  const HomeScreen({super.key, this.autoConnect = true});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('主板控制台')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.router, size: 64, color: Colors.teal),
              const SizedBox(height: 8),
              Text(
                '选择连接方式',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AutoLoginScreen(autoConnect: autoConnect),
                  ),
                ),
                icon: const Icon(Icons.wifi),
                label: const Text('wifi连接主板'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RemoteConfigScreen()),
                ),
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('远程连接主板'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
