import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'ws_connector.dart';

enum HubConnectionStatus { disconnected, connecting, connected, reconnecting }

typedef HubEventHandler = void Function(List<Object?> arguments);

/// Minimal ASP.NET Core SignalR JSON Hub Protocol v1 client over WebSocket.
/// Works identically across Android, iOS, and Flutter Web with zero native bridge bloat.
class SignalRHubClient {
  SignalRHubClient({
    required this.api,
    required this.hubPath,
    required this.tokenProvider,
    WebSocketFactory? socketFactory,
    this.heartbeatInterval = const Duration(seconds: 20),
    this.reconnectDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
    ],
  }) : _socketFactory = socketFactory ?? connectWebSocket;

  static const String recordSeparator = '\u001e';

  final ApiClient api;
  final String hubPath;
  final Future<String> Function() tokenProvider;
  final WebSocketFactory _socketFactory;
  final Duration heartbeatInterval;
  final List<Duration> reconnectDelays;

  final _handlers = <String, List<HubEventHandler>>{};
  final _statusListeners = <ValueChanged<HubConnectionStatus>>[];

  HubConnectionStatus _status = HubConnectionStatus.disconnected;
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  String _buffer = '';
  bool _handshakeDone = false;
  bool _stopped = true;
  int _reconnectAttempt = 0;
  int _generation = 0;

  HubConnectionStatus get status => _status;
  bool get isConnected =>
      _status == HubConnectionStatus.connected && _handshakeDone;

  void on(String target, HubEventHandler handler) {
    _handlers.putIfAbsent(target.toLowerCase(), () => []).add(handler);
  }

  void off(String target, HubEventHandler handler) {
    _handlers[target.toLowerCase()]?.remove(handler);
  }

  void addStatusListener(ValueChanged<HubConnectionStatus> listener) {
    _statusListeners.add(listener);
  }

  void removeStatusListener(ValueChanged<HubConnectionStatus> listener) {
    _statusListeners.remove(listener);
  }

  void _setStatus(HubConnectionStatus next) {
    if (_status == next) return;
    _status = next;
    for (final listener in List<ValueChanged<HubConnectionStatus>>.of(
      _statusListeners,
    )) {
      listener(next);
    }
  }

  Future<void> start() async {
    _stopped = false;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    await _connect(reconnecting: false);
  }

  Future<void> stop() async {
    _stopped = true;
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _teardownChannel();
    _setStatus(HubConnectionStatus.disconnected);
  }

  Future<void> invoke(
    String target, [
    List<Object?> arguments = const [],
  ]) async {
    if (!isConnected || _channel == null) return;
    final frame = jsonEncode({
      'type': 1,
      'target': target,
      'arguments': arguments,
    });
    try {
      _channel!.sink.add('$frame$recordSeparator');
    } catch (_) {
      // Transport disconnect will be handled by the stream listener.
    }
  }

  Future<void> _connect({required bool reconnecting}) async {
    final version = ++_generation;
    await _teardownChannel();
    if (_stopped) return;
    _setStatus(
      reconnecting
          ? HubConnectionStatus.reconnecting
          : HubConnectionStatus.connecting,
    );

    try {
      final token = await tokenProvider();
      if (_stopped || version != _generation) return;

      String? connectionToken;
      try {
        final negotiated = await api.request(
          '$hubPath/negotiate?negotiateVersion=1',
          method: 'POST',
          headers: {'Authorization': 'Bearer $token'},
          allowHub: true,
        );
        if (negotiated is Map<String, dynamic>) {
          final rawToken =
              negotiated['connectionToken'] ?? negotiated['connectionId'];
          if (rawToken is String && rawToken.isNotEmpty) {
            connectionToken = rawToken;
          }
        }
      } on ApiException catch (error) {
        if (error.statusCode == 401 || error.statusCode == 403) {
          _setStatus(HubConnectionStatus.disconnected);
          return;
        }
        // Fall through to direct WebSocket connect if negotiate is unavailable.
      }
      if (_stopped || version != _generation) return;

      final base = api.validatedOrigin();
      final wsScheme = base.scheme == 'https' ? 'wss' : 'ws';
      final query = <String, String>{
        'id': ?connectionToken,
        // Browser WebSockets cannot send Authorization headers during upgrade.
        if (kIsWeb) 'access_token': token,
      };
      final wsUri = Uri(
        scheme: wsScheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: hubPath,
        queryParameters: query.isEmpty ? null : query,
      );

      final channel = _socketFactory(
        wsUri,
        headers: kIsWeb ? null : {'Authorization': 'Bearer $token'},
      );
      _channel = channel;
      _buffer = '';
      _handshakeDone = false;

      _subscription = channel.stream.listen(
        (raw) => _handleData(raw, version),
        onError: (_) => _handleDisconnect(version),
        onDone: () => _handleDisconnect(version),
        cancelOnError: true,
      );

      channel.sink.add(
        '${jsonEncode({'protocol': 'json', 'version': 1})}$recordSeparator',
      );
    } catch (_) {
      if (!_stopped && version == _generation) {
        _scheduleReconnect(version);
      }
    }
  }

  void _handleData(Object? raw, int version) {
    if (_stopped || version != _generation) return;
    final chunk = raw is String
        ? raw
        : raw is List<int>
        ? utf8.decode(raw, allowMalformed: true)
        : '';
    if (chunk.isEmpty) return;
    _buffer += chunk;

    while (true) {
      final sep = _buffer.indexOf(recordSeparator);
      if (sep < 0) break;
      final frame = _buffer.substring(0, sep);
      _buffer = _buffer.substring(sep + 1);
      if (frame.trim().isEmpty) continue;
      _processFrame(frame, version);
    }
  }

  void _processFrame(String frame, int version) {
    Object? decoded;
    try {
      decoded = jsonDecode(frame);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    if (!_handshakeDone) {
      if (decoded['error'] is String &&
          (decoded['error'] as String).isNotEmpty) {
        _handleDisconnect(version);
        return;
      }
      _handshakeDone = true;
      _reconnectAttempt = 0;
      _setStatus(HubConnectionStatus.connected);
      _startHeartbeat(version);
      return;
    }

    final type = decoded['type'];
    if (type == 1) {
      // Invocation
      final target = decoded['target'];
      if (target is String && target.isNotEmpty) {
        final args = decoded['arguments'] is List
            ? List<Object?>.from(decoded['arguments'] as List)
            : const <Object?>[];
        final listeners = _handlers[target.toLowerCase()];
        if (listeners != null) {
          for (final handler in List<HubEventHandler>.of(listeners)) {
            handler(args);
          }
        }
      }
    } else if (type == 6) {
      // Ping keepalive
      try {
        _channel?.sink.add('{"type":6}$recordSeparator');
      } catch (_) {}
    } else if (type == 7) {
      // Close frame from server
      _handleDisconnect(version);
    }
  }

  void _startHeartbeat(int version) {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) {
      if (_stopped || version != _generation || !isConnected) return;
      try {
        _channel?.sink.add('{"type":6}$recordSeparator');
        unawaited(invoke('Ping'));
      } catch (_) {}
    });
  }

  void _handleDisconnect(int version) {
    if (_stopped || version != _generation) return;
    unawaited(_teardownChannel());
    _scheduleReconnect(version);
  }

  void _scheduleReconnect(int version) {
    if (_stopped || version != _generation) return;
    _setStatus(HubConnectionStatus.reconnecting);
    final delay =
        reconnectDelays[_reconnectAttempt < reconnectDelays.length
            ? _reconnectAttempt
            : reconnectDelays.length - 1];
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_stopped && version == _generation) {
        unawaited(_connect(reconnecting: true));
      }
    });
  }

  Future<void> _teardownChannel() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _handshakeDone = false;
    final sub = _subscription;
    _subscription = null;
    final ch = _channel;
    _channel = null;
    try {
      await sub?.cancel();
    } catch (_) {}
    try {
      await ch?.sink.close();
    } catch (_) {}
  }

  Future<void> dispose() => stop();
}
