import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/refresh_token_store.dart';

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
  AuthController({required this._api, required this._storage});

  final ApiClient _api;
  final RefreshTokenStore _storage;
  SessionStatus _status = SessionStatus.loading;
  _Session? _session;
  String? _savedRefreshToken;
  int _generation = 0;
  int? _refreshGeneration;
  Future<String>? _refreshFlight;
  Future<void>? _restoreFlight;
  Future<void> _persistence = Future<void>.value();
  bool _disposed = false;

  SessionStatus get status => _status;
  AuthUser? get user => _session?.user;

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
    final value = await _getAuthorized(path);
    if (value is! Map<String, dynamic>) {
      throw const ApiException('Phản hồi từ máy chủ không hợp lệ.');
    }
    return value;
  }

  Future<Object?> _getAuthorized(String path) async {
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
    Future<Object?> send(String bearer) =>
        _api.request(path, headers: {'Authorization': 'Bearer $bearer'});
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
