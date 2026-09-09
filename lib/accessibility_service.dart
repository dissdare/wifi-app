import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('board_control/network');

/// 无障碍服务是否已开启。
///
/// 仅在 Android 上有意义；非 Android 或平台通道不可用（测试/桌面环境）时
/// 返回 true，表示「无需提示」，从而静默跳过提示流程、不影响主功能。
Future<bool> isAccessibilityServiceEnabled() async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    return await _channel
        .invokeMethod<bool>('isAccessibilityServiceEnabled') ??
        true;
  } catch (_) {
    return true;
  }
}

/// 跳转到系统「无障碍」设置页，让用户开启本应用的服务。
Future<void> openAccessibilitySettings() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod('openAccessibilitySettings');
  } catch (_) {
    // 忽略：跳转失败不影响主流程
  }
}

/// 是否已经提示过用户开启无障碍服务（跨启动持久化）。
/// 异常/非 Android 时返回 true，避免重复弹框。
Future<bool> getA11yPromptShown() async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    return await _channel.invokeMethod<bool>('getA11yPromptShown') ?? true;
  } catch (_) {
    return true;
  }
}

/// 记录「已提示过」，保证只弹一次。
Future<void> setA11yPromptShown() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod('setA11yPromptShown');
  } catch (_) {
    // 忽略：记录失败最多导致下次再提示一次
  }
}
