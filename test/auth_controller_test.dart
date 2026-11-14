import 'dart:async';
import 'dart:convert';

import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/core/refresh_token_store.dart';
import 'package:ai_pms_mobile/features/auth/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _user = {
  'id': 7,
  'email': 'student@example.test',
  'fullName': 'Sinh viên',
  'roles': ['STUDENT'],
};

Map<String, Object?> _login([String suffix = 'initial']) => {
  'accessToken': 'access-$suffix',
  'refreshToken': 'refresh-$suffix',
  'tokenType': 'Bearer',
  'expiresAtUtc': DateTime.now()
      .add(const Duration(hours: 1))
      .toUtc()
      .toIso8601String(),
  'refreshTokenExpiresAtUtc': DateTime.now()
      .add(const Duration(days: 1))
      .toUtc()
      .toIso8601String(),
  'user': _user,
};

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Store implements RefreshTokenStore {
  _Store([this.value]);
  String? value;
  final List<String?> writes = [];

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async {
    value = token;
    writes.add(token);
  }

  @override
  Future<void> clear() async {
    value = null;
    writes.add(null);
  }
}

AuthController _auth(
  _Store store,
  Future<http.Response> Function(http.Request) handler,
) => AuthController(
  api: ApiClient(
    origin: 'https://api.example.test',
    client: MockClient(handler),
  ),
  storage: store,
);

void main() {
  test(
    'API rejects invalid origins, foreign hosts and path traversal',
    () async {
      var requests = 0;
      final mock = MockClient((_) async {
        requests++;
        return _json({});
      });
      for (final origin in [
        '',
        'file:///private',
        'https://user:secret@api.example.test',
        'https://api.example.test/api',
        'https://api.example.test?key=private',
      ]) {
        final api = ApiClient(origin: origin, client: mock);
        await expectLater(
          api.request('/api/v1/auth/me'),
          throwsA(isA<ApiException>()),
        );
      }
      final api = ApiClient(origin: 'https://api.example.test', client: mock);
      for (final path in [
        'https://attacker.test/api/v1/users',
        '//attacker.test/api/v1/users',
        '/api/v1/../../private',
        '/api/v1/projects/../auth/me',
        '/api/v1/%2e%2e/private',
        '/api/v1/\\attacker',
        '/api/v1/%5cattacker',
      ]) {
        await expectLater(
          api.request(path),
          throwsA(isA<ApiException>()),
          reason: path,
        );
      }
      expect(requests, 0);
    },
  );

  test('API disables redirects and hides server detail', () async {
    final api = ApiClient(
      origin: 'https://api.example.test',
      client: MockClient((request) async {
        expect(request.followRedirects, isFalse);
        expect(request.headers['Accept'], 'application/json');
        return _json({'detail': 'SQL password=private'}, 500);
      }),
    );
    await expectLater(
      api.request('/api/v1/auth/me'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'status', 500)
            .having(
              (error) => error.message,
              'safe message',
              isNot(contains('private')),
            ),
      ),
    );
  });

  test('API reports timeouts safely', () async {
    final api = ApiClient(
      origin: 'https://api.example.test',
      timeout: const Duration(milliseconds: 5),
      client: MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(
      api.request('/api/v1/auth/me'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('quá thời gian'),
        ),
      ),
    );
  });

  test('login verifies /me and persists only refresh token', () async {
    final store = _Store();
    final calls = <String>[];
    final auth = _auth(store, (request) async {
      calls.add(request.url.path);
      if (request.url.path.endsWith('/login')) {
        expect(jsonDecode(request.body), {
          'email': 'student@example.test',
          'password': 'password',
        });
        return _json(_login());
      }
      expect(request.headers['Authorization'], 'Bearer access-initial');
      return _json({..._user, 'fullName': 'Tên mới nhất'});
    });
    addTearDown(auth.dispose);
    await auth.signIn(' student@example.test ', 'password');
    expect(calls, ['/api/v1/auth/login', '/api/v1/auth/me']);
    expect(auth.status, SessionStatus.authenticated);
    expect(auth.user?.fullName, 'Tên mới nhất');
    expect(auth.user?.roles, ['STUDENT']);
    expect(store.writes, [null, 'refresh-initial']);
  });

  test(
    'concurrent 401 requests share one rotation and replay replacement',
    () async {
      final store = _Store();
      final rotation = Completer<http.Response>();
      final started = Completer<void>();
      var rotations = 0;
      final auth = _auth(store, (request) async {
        final path = request.url.path;
        if (path.endsWith('/login')) return _json(_login());
        if (path.endsWith('/me')) return _json(_user);
        if (path.endsWith('/refresh')) {
          rotations++;
          if (!started.isCompleted) started.complete();
          return rotation.future;
        }
        return request.headers['Authorization'] == 'Bearer access-rotated'
            ? _json({'ok': true})
            : _json({}, 401);
      });
      addTearDown(auth.dispose);
      await auth.signIn('student@example.test', 'password');
      final first = auth.getJson('/api/v1/projects');
      final second = auth.getJson('/api/v1/tasks');
      await started.future;
      await Future<void>.delayed(Duration.zero);
      expect(rotations, 1);
      rotation.complete(_json(_login('rotated')));
      expect(await Future.wait([first, second]), [
        {'ok': true},
        {'ok': true},
      ]);
      expect(store.value, 'refresh-rotated');
    },
  );

  test(
    'invalid refresh clears credentials and restore is single-flight',
    () async {
      final store = _Store('expired');
      var rotations = 0;
      final auth = _auth(store, (_) async {
        rotations++;
        return _json({}, 401);
      });
      addTearDown(auth.dispose);
      await Future.wait([auth.restore(), auth.restore()]);
      expect(rotations, 1);
      expect(auth.status, SessionStatus.anonymous);
      expect(store.value, isNull);
    },
  );

  test('transient restore failure retains the stored token', () async {
    final store = _Store('refresh-existing');
    final auth = _auth(
      store,
      (_) async => throw http.ClientException('offline'),
    );
    addTearDown(auth.dispose);
    await auth.restore();
    expect(auth.status, SessionStatus.anonymous);
    expect(store.value, 'refresh-existing');
  });

  test('403 denial preserves session without rotating credentials', () async {
    final store = _Store();
    var rotations = 0;
    final auth = _auth(store, (request) async {
      if (request.url.path.endsWith('/login')) return _json(_login());
      if (request.url.path.endsWith('/me')) return _json(_user);
      if (request.url.path.endsWith('/refresh')) rotations++;
      return _json({}, 403);
    });
    addTearDown(auth.dispose);
    await auth.signIn('student@example.test', 'password');
    await expectLater(
      auth.getJson('/api/v1/dashboards/admin'),
      throwsA(
        isA<ApiException>().having((error) => error.statusCode, 'status', 403),
      ),
    );
    expect(rotations, 0);
    expect(auth.status, SessionStatus.authenticated);
  });

  test('logout clears local state while server is offline', () async {
    final store = _Store();
    final auth = _auth(store, (request) async {
      if (request.url.path.endsWith('/login')) return _json(_login());
      if (request.url.path.endsWith('/me')) return _json(_user);
      throw http.ClientException('offline');
    });
    addTearDown(auth.dispose);
    await auth.signIn('student@example.test', 'password');
    await auth.signOut();
    expect(auth.status, SessionStatus.anonymous);
    expect(auth.user, isNull);
    expect(store.value, isNull);
  });

  test(
    'late refresh cannot restore logout and revokes replacement token',
    () async {
      final store = _Store();
      final rotation = Completer<http.Response>();
      final started = Completer<void>();
      final revoked = <String>[];
      final auth = _auth(store, (request) async {
        final path = request.url.path;
        if (path.endsWith('/login')) return _json(_login());
        if (path.endsWith('/me')) return _json(_user);
        if (path.endsWith('/refresh')) {
          started.complete();
          return rotation.future;
        }
        if (path.endsWith('/logout')) {
          revoked.add(
            (jsonDecode(request.body) as Map)['refreshToken'] as String,
          );
          return http.Response('', 204);
        }
        return _json({}, 401);
      });
      addTearDown(auth.dispose);
      await auth.signIn('student@example.test', 'password');
      final pending = auth.getJson('/api/v1/projects');
      final rejected = expectLater(pending, throwsA(isA<ApiException>()));
      await started.future;
      await auth.signOut();
      rotation.complete(_json(_login('late')));
      await rejected;
      await Future<void>.delayed(Duration.zero);
      expect(auth.status, SessionStatus.anonymous);
      expect(store.value, isNull);
      expect(revoked..sort(), ['refresh-initial', 'refresh-late']);
    },
  );
}
