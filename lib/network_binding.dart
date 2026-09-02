import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('board_control/network');

/// 尝试把应用的网络流量绑定到 WiFi 网络。
///
/// 主板 WiFi 是无外网的热点，安卓会把它判定为「无网络」并把流量切到蜂窝
/// 数据，导致连不上主板。这里主动绑定到 WiFi，保证 socket 走 WiFi。
/// 仅在 Android 上有实际动作；其它平台或失败/超时都静默忽略，不影响后续流程。
Future<void> bindProcessToWifi() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel
        .invokeMethod('bindToWifi')
        .timeout(const Duration(seconds: 5));
  } catch (_) {
    // 忽略：无 WiFi、模拟器、桌面等场景不影响后续连接
  }
}

/// 解除进程网络绑定，让 socket 回到系统默认网络（蜂窝 / 其它能上网的 WiFi）。
///
/// WiFi 直连会把进程持久绑定到无外网的主板热点；之后切换到能上网的网络时，
/// 进程仍绑在已失效的网络上，导致远程 frp 连接失败。远程连接前调用本方法解绑。
/// 仅 Android 上有实际动作，失败静默忽略。
Future<void> unbindProcessNetwork() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel
        .invokeMethod('unbindProcessNetwork')
        .timeout(const Duration(seconds: 5));
  } catch (_) {
    // 忽略：解绑失败不影响后续流程
  }
}

/// 保存上一次成功远程连接的设备序列号（持久化到 SharedPreferences）。
Future<void> saveLastSerial(String serial) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel
        .invokeMethod('saveSerial', {'serial': serial})
        .timeout(const Duration(seconds: 5));
  } catch (_) {
    // 忽略：保存失败不阻断连接流程
  }
}

/// 读取上一次成功远程连接的设备序列号；没有则返回 null。
Future<String?> getLastSerial() async {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final value = await _channel
        .invokeMethod<String>('getSerial')
        .timeout(const Duration(seconds: 5));
    return (value == null || value.isEmpty) ? null : value;
  } catch (_) {
    return null;
  }
}
