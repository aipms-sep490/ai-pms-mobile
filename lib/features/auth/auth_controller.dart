import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/refresh_token_store.dart';
import 'google_auth.dart';

enum SessionStatus { loading, authenticated, anonymous }

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.roles,
  });

  final int id;
  final String email;
  final String fullName;
  final List<String> roles;

  bool get isStudent => roles.contains('STUDENT');
  bool get isLecturer =>
      roles.contains('LECTURER') || roles.contains('SUPERVISOR');

  factory AuthUser.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['id'] is! int ||
        (value['id'] as int) <= 0 ||
        value['email'] is! String ||
        value['fullName'] is! String ||
        value['roles'] is! List ||
        !(value['roles'] as List).every((role) => role is String)) {
      throw const ApiException(
        'Thông tin tài khoản từ máy chủ không hợp lệ.',
        statusCode: 401,
      );
    }
    return AuthUser(
      id: value['id'] as int,
      email: value['email'] as String,
      fullName: value['fullName'] as String,
      roles: List<String>.unmodifiable((value['roles'] as List).cast<String>()),
    );
  }
}

class _Session {
  const _Session({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final AuthUser user;

  factory _Session.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) throw _invalidSession;
    final accessToken = value['accessToken'];
    final refreshToken = value['refreshToken'];
    final expiry = value['expiresAtUtc'];
    final refreshExpiry = value['refreshTokenExpiresAtUtc'];
    final expiresAt = expiry is String ? DateTime.tryParse(expiry) : null;
    final refreshExpiresAt = refreshExpiry is String
        ? DateTime.tryParse(refreshExpiry)
        : null;
    final now = DateTime.now();
    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty ||
        value['tokenType'] != 'Bearer' ||
        expiresAt == null ||
        !expiresAt.isAfter(now) ||
        refreshExpiresAt == null ||
        !refreshExpiresAt.isAfter(now)) {
      throw _invalidSession;
    }
    return _Session(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      user: AuthUser.fromJson(value['user']),
    );
  }

  _Session withUser(AuthUser current) => _Session(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt,
    user: current,
  );
}

const _invalidSession = ApiException(
  'Phiên đăng nhập từ máy chủ không hợp lệ.',
  statusCode: 401,
);
const _changedSession = ApiException(
  'Phiên đăng nhập đã thay đổi.',
  statusCode: 401,
);

class AuthController extends ChangeNotifier {
  AuthController({
    required this._api,
    required this._storage,
    GoogleIdTokenProvider? googleProvider,
    String? googleAuthOrigin,
  }) : _googleProvider = googleProvider ?? PlatformGoogleIdTokenProvider(),
       _googleAuthOrigin =
           (googleAuthOrigin ??
                   const String.fromEnvironment('GOOGLE_AUTH_ORIGIN'))
               .trim();

  final ApiClient _api;
  final RefreshTokenStore _storage;
  final GoogleIdTokenProvider _googleProvider;
  final String _googleAuthOrigin;
  SessionStatus _status = SessionStatus.loading;
  _Session? _session;
  String? _savedRefreshToken;
  int _generation = 0;
  int? _refreshGeneration;
  Future<String>? _refreshFlight;
  Future<void>? _restoreFlight;
  Future<void> _persistence = Future<void>.value();
  bool _disposed = false;

  ApiClient get api => _api;
  SessionStatus get status => _status;
  AuthUser? get user => _session?.user;

  Map<String, String> _googleOriginHeaders([String? cookie]) {
    final origin = _googleAuthOrigin.isNotEmpty
        ? _googleAuthOrigin
        : _api.origin;
    return {
      if (!kIsWeb && origin.isNotEmpty) 'Origin': origin,
      if (!kIsWeb && cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  void _publish(SessionStatus next) {
    if (_disposed) return;
    _status = next;
    notifyListeners();
  }

  Future<void> _persist(String? token, int version) {
    final operation = _persistence.catchError((Object _) {}).then((_) async {
      if (version != _generation) return;
      try {
        if (token == null) {
          await _storage.clear();
        } else {
          await _storage.write(token);
        }
      } catch (_) {
        throw const ApiException(
          'Không truy cập được bộ nhớ an toàn trên thiết bị. Vui lòng thử lại.',
        );
      }
    });
    _persistence = operation;
    return operation;
  }

  Future<void> _clear() async {
    _generation += 1;
    _session = null;
    _savedRefreshToken = null;
    _publish(SessionStatus.anonymous);
    await _persist(null, _generation);
  }

  Future<void> _revoke(String token) async {
    try {
      await _api.request(
        '/api/v1/auth/logout',
        method: 'POST',
        body: {'refreshToken': token},
      );
    } catch (_) {
      // Local logout still completes if the server is unreachable.
    }
  }

  Future<String> _adopt(_Session next, int version) async {
    if (version != _generation || _disposed) {
      unawaited(_revoke(next.refreshToken));
      throw _changedSession;
    }
    try {
      await _persist(next.refreshToken, version);
    } catch (_) {
      if (version == _generation) {
        await _clear().catchError((Object _) {});
      }
      unawaited(_revoke(next.refreshToken));
      throw const ApiException(
        'Không lưu được phiên đăng nhập an toàn trên thiết bị. Vui lòng thử lại.',
      );
    }
    if (version != _generation || _disposed) {
      unawaited(_revoke(next.refreshToken));
      throw _changedSession;
    }
    _session = next;
    _savedRefreshToken = next.refreshToken;
    _publish(SessionStatus.authenticated);
    return next.accessToken;
  }

  Future<String> _refresh() {
    final version = _generation;
    if (_refreshGeneration == version && _refreshFlight != null) {
      return _refreshFlight!;
    }
    final token = _session?.refreshToken ?? _savedRefreshToken;
    if (token == null) {
      return Future.error(
        const ApiException('Vui lòng đăng nhập để tiếp tục.', statusCode: 401),
      );
    }
    _refreshGeneration = version;
    final operation = _rotate(token, version).whenComplete(() {
      if (_refreshGeneration == version) _refreshFlight = null;
    });
    _refreshFlight = operation;
    return operation;
  }

  Future<String> _rotate(String token, int version) async {
    try {
      final value = await _api.request(
        '/api/v1/auth/refresh',
        method: 'POST',
        body: {'refreshToken': token},
      );
      return await _adopt(_Session.fromJson(value), version);
    } on ApiException catch (error) {
      if (version == _generation && [401, 403].contains(error.statusCode)) {
        await _clear();
      }
      rethrow;
    }
  }

  /// Returns a valid bearer token for foreground SignalR / streaming calls.
  Future<String> validAccessToken() async {
    final current = _session;
    if (current == null) {
      throw const ApiException(
        'Vui lòng đăng nhập để tiếp tục.',
        statusCode: 401,
      );
    }
    if (!current.expiresAt.isAfter(
      DateTime.now().add(const Duration(seconds: 20)),
    )) {
      return _refresh();
    }
    return current.accessToken;
  }

  Future<void> restore() => _restoreFlight ??= _restore();

  Future<void> _restore() async {
    final version = _generation;
    try {
      final token = await _storage.read();
      if (version != _generation || _disposed) return;
      _savedRefreshToken = token;
      if (token == null) {
        _publish(SessionStatus.anonymous);
      } else {
        await _refresh();
      }
    } catch (_) {
      // Invalid refresh tokens are cleared; transient network failures retain storage.
      if (version == _generation) _publish(SessionStatus.anonymous);
    }
  }

  Future<void> signIn(String email, String password) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const ApiException('Vui lòng nhập email và mật khẩu.');
    }
    final version = ++_generation;
    _session = null;
    _savedRefreshToken = null;
    _publish(SessionStatus.anonymous);
    await _persist(null, version);
    final value = await _api.request(
      '/api/v1/auth/login',
      method: 'POST',
      body: {'email': email.trim(), 'password': password},
    );
    await _completeLogin(value, version);
  }

  Future<void> signInWithGoogle() async {
    final version = ++_generation;
    _session = null;
    _savedRefreshToken = null;
    _publish(SessionStatus.anonymous);
    await _persist(null, version);
    try {
      final challengeResponse = await _api.requestRaw(
        '/api/v1/auth/google/challenge',
        method: 'POST',
        headers: _googleOriginHeaders(),
        body: {'purpose': 'LOGIN'},
      );
      if (version != _generation || _disposed) throw _changedSession;
      final challenge = GoogleChallengeData.fromResponse(challengeResponse);
      final idToken = await _googleProvider.obtainIdToken(
        clientId: challenge.clientId,
        nonce: challenge.nonce,
      );
      if (version != _generation || _disposed) throw _changedSession;
      if (!challenge.expiresAtUtc.isAfter(DateTime.now().toUtc())) {
        throw const ApiException(
          'Phiên đăng nhập Google đã hết hạn. Vui lòng thử lại.',
          statusCode: 401,
        );
      }
      final loginResponse = await _api.request(
        '/api/v1/auth/google/login',
        method: 'POST',
        headers: _googleOriginHeaders(challenge.bindingCookie),
        body: {'challengeId': challenge.challengeId, 'idToken': idToken},
      );
      await _completeLogin(loginResponse, version);
    } catch (error) {
      throw ApiException(
        googleAuthErrorMessage(error),
        statusCode: error is ApiException ? error.statusCode : 0,
      );
    }
  }

  Future<void> linkGoogleAccount(String currentPassword) async {
    if (currentPassword.isEmpty) {
      throw const ApiException('Nhập mật khẩu hiện tại để liên kết Google.');
    }
    final token = await validAccessToken();
    try {
      final challengeResponse = await _api.requestRaw(
        '/api/v1/auth/google/challenge',
        method: 'POST',
        headers: {'Authorization': 'Bearer $token', ..._googleOriginHeaders()},
        body: {'purpose': 'LINK'},
      );
      final challenge = GoogleChallengeData.fromResponse(challengeResponse);
      final idToken = await _googleProvider.obtainIdToken(
        clientId: challenge.clientId,
        nonce: challenge.nonce,
      );
      await _api.request(
        '/api/v1/auth/google/link',
        method: 'POST',
        headers: {
          'Authorization': 'Bearer ${await validAccessToken()}',
          ..._googleOriginHeaders(challenge.bindingCookie),
        },
        body: {
          'challengeId': challenge.challengeId,
          'idToken': idToken,
          'currentPassword': currentPassword,
        },
      );
    } catch (error) {
      throw ApiException(
        googleAuthErrorMessage(error),
        statusCode: error is ApiException ? error.statusCode : 0,
      );
    }
  }

  Future<void> unlinkGoogleAccount(String currentPassword) async {
    if (currentPassword.isEmpty) {
      throw const ApiException('Nhập mật khẩu hiện tại để hủy liên kết.');
    }
    final token = await validAccessToken();
    try {
      await _api.request(
        '/api/v1/auth/google/unlink',
        method: 'POST',
        headers: {'Authorization': 'Bearer $token', ..._googleOriginHeaders()},
        body: {'currentPassword': currentPassword},
      );
    } catch (error) {
      throw ApiException(
        googleAuthErrorMessage(error),
        statusCode: error is ApiException ? error.statusCode : 0,
      );
    }
  }

  Future<void> _completeLogin(Object? value, int version) async {
    try {
      final next = _Session.fromJson(value);
      final current = await _api.request(
        '/api/v1/auth/me',
        headers: {'Authorization': 'Bearer ${next.accessToken}'},
      );
      await _adopt(next.withUser(AuthUser.fromJson(current)), version);
    } catch (_) {
      if (value is Map<String, dynamic> && value['refreshToken'] is String) {
        unawaited(_revoke(value['refreshToken'] as String));
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    final token = _session?.refreshToken ?? _savedRefreshToken;
    try {
      await _clear();
    } finally {
      if (token != null) await _revoke(token);
    }
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final value = await request(path);
    if (value is! Map<String, dynamic>) {
      throw const ApiException('Phản hồi từ máy chủ không hợp lệ.');
    }
    return value;
  }

  Stream<String> requestNdjsonStream(
    String path, {
    Map<String, String>? fields,
    List<ApiUpload> uploads = const [],
    Duration? requestTimeout,
  }) async* {
    final version = _generation;
    final token = await validAccessToken();
    if (version != _generation || _disposed) throw _changedSession;
    await for (final line in _api.requestNdjsonStream(
      path,
      headers: {'Authorization': 'Bearer $token'},
      fields: fields,
      uploads: uploads,
      requestTimeout: requestTimeout,
    )) {
      if (version != _generation || _disposed) throw _changedSession;
      yield line;
    }
  }

  Future<Object?> request(
    String path, {
    String method = 'GET',
    Object? body,
    Duration? requestTimeout,
    ApiUpload? upload,
    bool binary = false,
  }) async {
    final version = _generation;
    final current = _session;
    if (current == null) {
      throw const ApiException(
        'Vui lòng đăng nhập để tiếp tục.',
        statusCode: 401,
      );
    }
    var token = current.accessToken;
    if (!current.expiresAt.isAfter(
      DateTime.now().add(const Duration(seconds: 15)),
    )) {
      token = await _refresh();
    }
    Future<Object?> send(String bearer) async {
      if (version != _generation || _disposed) throw _changedSession;
      final result = await _api.request(
        path,
        method: method,
        body: body,
        requestTimeout: requestTimeout,
        upload: upload,
        binary: binary,
        headers: {'Authorization': 'Bearer $bearer'},
      );
      if (version != _generation || _disposed) throw _changedSession;
      return result;
    }

    try {
      return await send(token);
    } on ApiException catch (error) {
      if (error.statusCode != 401 || version != _generation) rethrow;
      final updated = _session;
      final replacement = updated != null && updated.accessToken != token
          ? updated.accessToken
          : await _refresh();
      if (version != _generation) throw _changedSession;
      try {
        return await send(replacement);
      } on ApiException catch (retryError) {
        if (version == _generation && retryError.statusCode == 401) {
          await _clear();
        }
        rethrow;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}
