import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

/// 一条本地端口转发隧道：把手机本地的 [localPort] 通过 SSH 转发到
/// [remoteHost]:[remotePort]。
///
/// 等价于 `ssh -L 127.0.0.1:本地端口:目标IP:目标端口`。[remoteHost] 是
/// **主板视角** 的局域网地址（SSH 服务器负责去连接它），不是手机的地址。
class LocalTunnel {
  final SSHClient client;
  final String remoteHost;
  final int remotePort;
  final int localPort;

  LocalTunnel({
    required this.client,
    required this.remoteHost,
    required this.remotePort,
    required this.localPort,
  });

  ServerSocket? _server;
  final Set<_ForwardedConn> _conns = {};

  /// 心跳探测定时器：周期性验证目标仍可达。
  Timer? _probeTimer;
  bool _probing = false;

  /// 探测连续失败累计的起始时间；null 表示当前可达。
  DateTime? _failSince;

  /// 隧道因目标不可达而自动断开时回调（用于通知 UI 刷新按钮颜色）。
  void Function()? onClosed;

  bool get isRunning => _server != null;

  /// 浏览器访问的本地网址，如 `http://127.0.0.1:33876`。
  String get localUrl => 'http://127.0.0.1:$localPort';

  /// 启动监听。端口被占用等错误会向上抛出。
  ///
  /// 建立前先做一次连通性探测：通过 SSH 让主板去连 [remoteHost]:[remotePort]。
  /// 目标 IP 不存在或端口不通时，SSH 服务器会拒绝 direct-tcpip 通道，
  /// forwardLocal 抛异常，隧道不建立。这样「建立成功」等价于主板确实
  /// 能和目标设备通信（比 ping 更严格：ping 通但端口没开照样连不上）。
  Future<void> start() async {
    if (_server != null) return;

    // 连通性探测：能连上目标才算成功。探测通道用完立即销毁，
    // 不等对端关闭（目标设备不会主动关这个 TCP 连接）。
    await _probeTarget();

    final server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, localPort);
    _server = server;
    server.listen(_onConnection, onError: (_) {});

    // 启动心跳：运行期间周期性验证目标仍可达。
    _probeTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _heartbeat(),
    );
  }

  /// 通过 SSH 让主板去连目标，验证连通性。失败抛异常。
  Future<void> _probeTarget() async {
    final probe = await client
        .forwardLocal(remoteHost, remotePort)
        .timeout(const Duration(seconds: 8));
    probe.destroy();
  }

  /// 心跳探测：目标仍可达则清零失败累计；连续失败满 5 秒则主动断开。
  Future<void> _heartbeat() async {
    if (_probing || _server == null) return;
    _probing = true;
    try {
      await _probeTarget();
      _failSince = null;
    } catch (_) {
      final now = DateTime.now();
      _failSince ??= now;
      if (now.difference(_failSince!) >= const Duration(seconds: 5)) {
        await stop();
        onClosed?.call();
      }
    } finally {
      _probing = false;
    }
  }

  Future<void> _onConnection(Socket local) async {
    try {
      final channel = await client.forwardLocal(remoteHost, remotePort);
      late final _ForwardedConn conn;
      conn = _ForwardedConn(
        local,
        channel,
        () => _conns.remove(conn),
      );
      _conns.add(conn);
    } catch (_) {
      local.destroy();
    }
  }

  /// 停止监听并关闭所有转发中的连接。
  Future<void> stop() async {
    _probeTimer?.cancel();
    _probeTimer = null;
    _failSince = null;
    final server = _server;
    _server = null;
    await server?.close();
    for (final conn in List.of(_conns)) {
      conn.dispose();
    }
    _conns.clear();
  }
}

/// 一条正在转发数据的连接：本地 socket 与 SSH 转发通道的双向管道。
class _ForwardedConn {
  final Socket _local;
  final SSHForwardChannel _channel;
  final void Function() _onClose;
  bool _disposed = false;

  _ForwardedConn(this._local, this._channel, this._onClose) {
    // 远端（主板局域网设备）→ 本地（手机浏览器）
    _channel.stream.listen(
      (data) {
        try {
          _local.add(data);
        } catch (_) {
          dispose();
        }
      },
      onError: (_) => dispose(),
      onDone: dispose,
      cancelOnError: true,
    );
    // 本地（手机浏览器）→ 远端
    _local.listen(
      (data) {
        try {
          _channel.sink.add(data);
        } catch (_) {
          dispose();
        }
      },
      onError: (_) => dispose(),
      onDone: dispose,
      cancelOnError: true,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _local.destroy();
    } catch (_) {}
    try {
      _channel.destroy();
    } catch (_) {}
    _onClose();
  }
}
