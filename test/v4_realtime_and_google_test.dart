import 'dart:async';
import 'dart:convert';

import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/core/realtime_hub_manager.dart';
import 'package:ai_pms_mobile/core/refresh_token_store.dart';
import 'package:ai_pms_mobile/core/signalr_client.dart';
import 'package:ai_pms_mobile/features/auth/auth_controller.dart';
import 'package:ai_pms_mobile/features/auth/google_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/mobile_fixtures.dart';

class _FakeGoogleProvider implements GoogleIdTokenProvider {
  _FakeGoogleProvider(this.idToken);
  final String idToken;
  String? receivedClientId;
  String? receivedNonce;

  @override
  Future<String> obtainIdToken({
    required String clientId,
    required String nonce,
  }) async {
    receivedClientId = clientId;
    receivedNonce = nonce;
    return idToken;
  }
}

class _FakeWebSocketChannel implements WebSocketChannel {
  _FakeWebSocketChannel() : _incoming = StreamController<Object?>.broadcast() {
    _sink = _FakeWebSocketSink(_incoming);
  }

  final StreamController<Object?> _incoming;
  late final _FakeWebSocketSink _sink;

  void sendFromServer(String payload) {
    if (!_incoming.isClosed) {
      _incoming.add(payload);
    }
  }

  @override
  Stream<Object?> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  int? get closeCode => _sink.closed ? 1000 : null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink(this._incoming);
  final StreamController<Object?> _incoming;
  final Completer<void> _done = Completer<void>();
  bool closed = false;
  final List<Object?> added = [];

  @override
  void add(Object? data) {
    added.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<void> get done => _done.future;
}

void main() {
  test(
    'ApiClient maps V4 422/409 workflow error codes without leaking raw detail',
    () async {
      final codes = <String, String>{
        'BLOCKER_REASON_TOO_SHORT': 'tối thiểu 15 ký tự',
        'EVIDENCE_REQUIRED': 'minh chứng hợp lệ',
        'TASK_DEPENDENCY_IMPACT_PENDING': 'ảnh hưởng phụ thuộc',
        'REPORT_LOCKED': 'đã bị khóa',
        'PEER_EVAL_REASON_TOO_SHORT': 'tối thiểu 30 ký tự',
      };
      for (final entry in codes.entries) {
        final api = ApiClient(
          origin: 'https://api.example.test',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'code': entry.key,
                'detail': 'SECRET_INTERNAL_SQL_STACK_TRACE',
              }),
              entry.key == 'REPORT_LOCKED' ? 409 : 422,
            ),
          ),
        );
        await expectLater(
          () => api.request('/api/v1/tasks/12/status', method: 'PUT'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.errorCode, 'errorCode', entry.key)
                .having((e) => e.message, 'message', contains(entry.value))
                .having(
                  (e) => e.message,
                  'no leak',
                  isNot(contains('SECRET_INTERNAL')),
                ),
          ),
        );
      }
    },
  );

  test('Google Sign-In performs challenge, binds cookie, sends idToken and verifies /me', () async {
    final google = _FakeGoogleProvider('google-id-token-123');
    String? sentCookie;
    String? sentOrigin;
    Map<String, dynamic>? sentLoginBody;
    final storage = MemoryRefreshTokenStore();
    final api = ApiClient(
      origin: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/google/challenge') {
          sentOrigin = request.headers['Origin'];
          return http.Response(
            jsonEncode({
              'challengeId': '11111111-1111-1111-1111-111111111111',
              'clientId': 'test-client.apps.googleusercontent.com',
              'nonce': 'nonce-abc',
              'expiresAtUtc': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            }),
            200,
            headers: {
              'content-type': 'application/json',
              'set-cookie': 'aipms-google-binding=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; Path=/api/v1/auth/google; HttpOnly',
            },
          );
        }
        if (request.url.path == '/api/v1/auth/google/login') {
          sentCookie = request.headers['Cookie'];
          sentLoginBody = jsonDecode(request.body) as Map<String, dynamic>;
          return json(loginFixture());
        }
        if (request.url.path == '/api/v1/auth/me') {
          return json(user);
        }
        return json({}, 404);
      }),
    );
    final auth = AuthController(
      api: api,
      storage: storage,
      googleProvider: google,
      googleAuthOrigin: 'https://web.example.test',
    );
    await auth.signInWithGoogle();
    expect(auth.status, SessionStatus.authenticated);
    expect(google.receivedClientId, 'test-client.apps.googleusercontent.com');
    expect(google.receivedNonce, 'nonce-abc');
    expect(sentOrigin, 'https://web.example.test');
    expect(sentCookie, startsWith('aipms-google-binding=aaaa'));
    expect(sentLoginBody?['idToken'], 'google-id-token-123');
    expect(await storage.read(), 'fixture-refresh');
    auth.dispose();
  });

  test('SignalRHubClient handshakes, dispatches events, invokes WatchConversation and stops cleanly', () async {
    final fakeChannel = _FakeWebSocketChannel();
    Uri? connectedUri;
    Map<String, String>? connectedHeaders;
    final api = ApiClient(
      origin: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.url.path == '/hubs/chat/negotiate') {
          return json({'connectionToken': 'conn-xyz'});
        }
        return json({}, 404);
      }),
    );

    final client = SignalRHubClient(
      api: api,
      hubPath: '/hubs/chat',
      tokenProvider: () async => 'jwt-token-1',
      socketFactory: (uri, {headers}) {
        connectedUri = uri;
        connectedHeaders = headers;
        return fakeChannel;
      },
    );

    final events = <Map<String, dynamic>>[];
    client.on('MessagesChanged', (args) {
      events.add(args.first as Map<String, dynamic>);
    });

    await client.start();
    expect(connectedUri?.scheme, 'wss');
    expect(connectedUri?.path, '/hubs/chat');
    expect(connectedUri?.queryParameters['id'], 'conn-xyz');
    expect(connectedHeaders?['Authorization'], 'Bearer jwt-token-1');

    fakeChannel.sendFromServer('{}${SignalRHubClient.recordSeparator}');
    await Future<void>.delayed(Duration.zero);
    expect(client.isConnected, isTrue);

    await client.invoke('WatchConversation', ['9007199254740993']);
    final outgoing = (fakeChannel.sink as _FakeWebSocketSink).added;
    expect(
      outgoing.any(
        (frame) =>
            frame is String &&
            frame.contains('"target":"WatchConversation"') &&
            frame.contains('9007199254740993'),
      ),
      isTrue,
    );

    fakeChannel.sendFromServer(
      '${jsonEncode({
        'type': 1,
        'target': 'MessagesChanged',
        'arguments': [
          {'conversationId': '9007199254740993'},
        ],
      })}${SignalRHubClient.recordSeparator}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.single['conversationId'], '9007199254740993');

    await client.stop();
    expect(client.status, HubConnectionStatus.disconnected);
  });

  test('RealtimeHubManager tracks unread notifications and tears down on logout', () async {
    final channels = <String, _FakeWebSocketChannel>{};
    final api = ApiClient(
      origin: 'https://api.example.test',
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return json(loginFixture());
        }
        if (request.url.path == '/api/v1/auth/me') return json(user);
        if (request.url.path == '/api/v1/auth/logout') {
          return http.Response('', 204);
        }
        if (request.url.path.endsWith('/negotiate')) {
          return json({'connectionToken': 'tok-1'});
        }
        return json({}, 404);
      }),
    );
    final auth = AuthController(api: api, storage: MemoryRefreshTokenStore());
    await auth.signIn('student@example.test', 'secret');

    final manager = RealtimeHubManager(
      auth: auth,
      socketFactory: (uri, {headers}) {
        final ch = _FakeWebSocketChannel();
        channels[uri.path] = ch;
        return ch;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(channels.keys, containsAll(['/hubs/chat', '/hubs/notifications']));

    channels['/hubs/notifications']!.sendFromServer(
      '{}${SignalRHubClient.recordSeparator}',
    );
    channels['/hubs/notifications']!.sendFromServer(
      '${jsonEncode({
        'type': 1,
        'target': 'NotificationReceived',
        'arguments': [
          {'notificationId': 42, 'title': 'Báo cáo đã được nhận xét', 'content': 'GVHD vừa phản hồi báo cáo tuần 5.'},
        ],
      })}${SignalRHubClient.recordSeparator}',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(manager.notificationConnected, isTrue);
    expect(manager.unreadNotificationBump, 1);
    expect(manager.latestNotification?.notificationId, 42);

    await auth.signOut();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(manager.unreadNotificationBump, 0);
    expect(manager.notificationConnected, isFalse);
    manager.dispose();
    auth.dispose();
  });
}
