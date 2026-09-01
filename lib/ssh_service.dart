import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

/// 单条指令的执行结果。
class CommandResult {
  final int? exitCode;
  final String stdout;
  final String stderr;

  const CommandResult({
    this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// 连接尝试被主动取消（内部信号，不对外暴露）。
class _Cancelled implements Exception {
  @override
  String toString() => '连接已取消';
}

/// 一次可取消的 SSH 连接尝试。
///
/// [start] 成功返回已认证的 [SSHClient]，失败抛出异常。
/// [cancel] 可随时调用以中断尝试：销毁底层 socket，让进行中的
/// 连接/认证立即失败。若仍处于 TCP 建连阶段（拿不到 socket），
/// 则在建连返回后立即放弃，最多等待 [timeout]。
class SshConnectionAttempt {
  final String host;
  final int port;
  final String username;
  final String password;
  final Duration timeout;

  SSHSocket? _socket;
  SSHClient? _client;
  bool _cancelled = false;

  SshConnectionAttempt({
    required this.host,
    this.port = 22,
    required this.username,
    required this.password,
    this.timeout = const Duration(seconds: 8),
  });

  Future<SSHClient> start() async {
    SSHSocket? socket;
    SSHClient? client;
    try {
      if (_cancelled) throw _Cancelled();

      socket = await SSHSocket.connect(host, port, timeout: timeout);
      _socket = socket;
      if (_cancelled) throw _Cancelled();

      client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
        // 关闭内置 keepalive（它无超时，静默断连时检测不到），
        // 改由 SSHService 用带超时的 ping 探测来检测断开。
        keepAliveInterval: null,
        // 未设置 onVerifyHostKey 时默认信任任意主机密钥，
        // 对内部/实验室设备足够；若设备对外暴露建议校验指纹。
      );
      _client = client;

      await client.authenticated;
      if (_cancelled) throw _Cancelled();
      return client;
    } catch (_) {
      client?.close();
      socket?.destroy();
      rethrow;
    }
  }

  void cancel() {
    _cancelled = true;
    _socket?.destroy();
    _client?.close();
  }
}

/// 一次竞速的胜出结果。
class ConnectResult {
  final SSHClient client;
  final String host;
  final int port;

  ConnectResult({required this.client, required this.host, required this.port});
}

/// 并发尝试多个连接，返回最先成功的一个 [ConnectResult]；
/// 其余尝试会被取消。全部失败则抛出 [StateError]。
Future<ConnectResult> raceConnect(List<SshConnectionAttempt> attempts) {
  if (attempts.isEmpty) {
    return Future.error(StateError('没有可用的连接目标'));
  }

  final completer = Completer<ConnectResult>();
  var remaining = attempts.length;
  var won = false;

  for (final a in attempts) {
    a.start().then(
      (client) {
        if (won) {
          client.close();
          return;
        }
        won = true;
        for (final o in attempts) {
          if (!identical(o, a)) o.cancel();
        }
        if (!completer.isCompleted) {
          completer.complete(
            ConnectResult(client: client, host: a.host, port: a.port),
          );
        }
      },
      onError: (Object e) {
        remaining--;
        if (remaining == 0 && !completer.isCompleted) {
          completer.completeError(StateError('所有地址均连接失败'));
        }
      },
    );
  }

  return completer.future;
}

/// 封装 SSH 连接与指令执行。
class SSHService {
  SSHClient? _client;
  String? _host;
  Timer? _keepAliveTimer;
  bool _probing = false;
  final List<void Function()> _disconnectListeners = [];

  bool get isConnected => _client != null && !_client!.isClosed;

  /// 当前连接的 IP 地址（用于界面显示）。
  String? get host => _host;

  /// 注册连接断开监听（意外断开时回调，用于 UI 更新状态）。
  void addDisconnectListener(void Function() listener) {
    _disconnectListeners.add(listener);
  }

  void removeDisconnectListener(void Function() listener) {
    _disconnectListeners.remove(listener);
  }

  /// 打开一个交互式 PTY shell（用于实时终端）。
  Future<SSHSession> openShell({int width = 120, int height = 40}) async {
    final client = _client;
    if (client == null) {
      throw StateError('尚未连接');
    }
    return client.shell(pty: SSHPtyConfig(width: width, height: height));
  }

  /// 接管一个已认证的连接（自动登录竞速成功后使用）。
  void adopt(SSHClient client, {String? host}) {
    _client?.close();
    _client = client;
    _host = host;
    _watchConnection();
    _startKeepAlive();
  }

  /// 建立 SSH 连接并完成认证（手动连接）。
  ///
  /// 认证失败或网络不通会抛出异常，由调用方处理并提示用户。
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    final attempt = SshConnectionAttempt(
      host: host,
      port: port,
      username: username,
      password: password,
      timeout: const Duration(seconds: 10),
    );
    _client = await attempt.start();
    _host = host;
    _watchConnection();
    _startKeepAlive();
  }

  /// 监听底层连接正常关闭（收到 FIN/RST 或 socket 出错）。
  void _watchConnection() {
    final client = _client;
    if (client == null) return;
    unawaited(client.done.then(
      (_) => _markDisconnected(),
      onError: (_) => _markDisconnected(),
    ));
  }

  /// 定期发送带超时的 keepalive，检测静默断开（如 WiFi 断开，
  /// TCP 收不到 FIN/RST，socket.done 不会触发）。
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _probe(),
    );
  }

  Future<void> _probe() async {
    if (_probing) return;
    _probing = true;
    try {
      final client = _client;
      if (client == null || client.isClosed) {
        _markDisconnected();
        return;
      }
      try {
        // ping 发送 keepalive 并等待服务器回复；断开时回复不会来，
        // 用超时兜底判定连接已死。
        await client.ping().timeout(const Duration(seconds: 4));
      } catch (_) {
        _markDisconnected();
      }
    } finally {
      _probing = false;
    }
  }

  /// 标记断开：停止探测、关闭连接并通知所有监听者。
  void _markDisconnected() {
    if (_client == null && _keepAliveTimer == null) return;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    final client = _client;
    _client = null;
    _host = null;
    // 先通知 listener（UI 立即更新状态），再关闭连接。
    // close() 可能因底层已关闭而抛异常，放最后并忽略，避免阻断通知。
    final listeners = List.of(_disconnectListeners);
    for (final l in listeners) {
      l();
    }
    try {
      client?.close();
    } catch (_) {}
  }

  /// 在已建立的连接上执行一条指令，返回其输出与退出码。
  Future<CommandResult> runCommand(String command) async {
    final client = _client;
    if (client == null) {
      throw StateError('尚未连接');
    }

    final session = await client.execute(command);
    final out = await utf8.decodeStream(session.stdout);
    final err = await utf8.decodeStream(session.stderr);
    await session.done;

    return CommandResult(
      exitCode: session.exitCode,
      stdout: out,
      stderr: err,
    );
  }

  /// 断开连接。
  void disconnect() {
    _markDisconnected();
  }
}
