import 'package:flutter/material.dart';

import 'accessibility_service.dart';
import 'auto_login_screen.dart';
import 'remote_config_screen.dart';

/// 首页：选择连接方式——本地 WiFi 直连 或 远程 frp 连接。
class HomeScreen extends StatefulWidget {
  /// 点击「wifi连接主板」进入自动登录页后，是否自动尝试连接。
  final bool autoConnect;

  const HomeScreen({super.key, this.autoConnect = true});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _maybePromptAccessibility();
  }

  /// 首次进入首页且无障碍服务未开启时，弹一次开启提示。
  ///
  /// 逻辑：已提示过 → 跳过；已开启 → 跳过；否则记一次「已提示」并弹框。
  /// 非 Android 或平台通道不可用（测试/桌面）时各方法内部静默短路，不影响主流程。
  Future<void> _maybePromptAccessibility() async {
    final alreadyShown = await getA11yPromptShown();
    if (alreadyShown) return;

    final enabled = await isAccessibilityServiceEnabled();
    if (enabled) return;

    if (!mounted) return;
    await setA11yPromptShown();
    if (!mounted) return;
    _showAccessibilityDialog();
  }

  void _showAccessibilityDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开启后台运行'),
        content: const Text(
          '开启无障碍服务后，切换到其他应用时本应用会在后台保持运行，'
          '已建立的连接不会断开。\n\n'
          '不开启也不影响正常使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAccessibilitySettings();
            },
            child: const Text('去开启'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('主板控制台'),
        actions: [
          // 右上角「权限」按钮：跳转系统无障碍设置页，手动开启后台保活服务。
          TextButton(
            onPressed: () => openAccessibilitySettings(),
            child: const Text('权限'),
          ),
        ],
      ),
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
                    builder: (_) => AutoLoginScreen(autoConnect: widget.autoConnect),
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
