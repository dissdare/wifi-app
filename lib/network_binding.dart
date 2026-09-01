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
