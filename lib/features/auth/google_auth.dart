import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/api_client.dart';

class GoogleChallengeData {
  const GoogleChallengeData({
    required this.challengeId,
    required this.clientId,
    required this.nonce,
    required this.expiresAtUtc,
    this.bindingCookie,
  });

  final String challengeId;
  final String clientId;
  final String nonce;
  final DateTime expiresAtUtc;
  final String? bindingCookie;

  factory GoogleChallengeData.fromResponse(ApiResponseData response) {
    final body = response.body;
    if (body is! Map<String, dynamic>) {
      throw const ApiException('Phản hồi thử thách Google không hợp lệ.');
    }
    final challengeId = body['challengeId'];
    final clientId = body['clientId'];
    final nonce = body['nonce'];
    final expiry = body['expiresAtUtc'];
    final expiresAt = expiry is String ? DateTime.tryParse(expiry) : null;
    if (challengeId is! String ||
        challengeId.isEmpty ||
        clientId is! String ||
        clientId.isEmpty ||
        nonce is! String ||
        nonce.isEmpty ||
        expiresAt == null) {
      throw const ApiException('Phản hồi thử thách Google không đầy đủ.');
    }
    return GoogleChallengeData(
      challengeId: challengeId,
      clientId: clientId,
      nonce: nonce,
      expiresAtUtc: expiresAt,
      bindingCookie: extractGoogleBindingCookie(response.headers),
    );
  }
}

/// Extracts `aipms-google-binding=...` from HTTP response `set-cookie` header.
String? extractGoogleBindingCookie(Map<String, String> headers) {
  final raw = headers['set-cookie'] ?? headers['Set-Cookie'];
  if (raw == null || raw.isEmpty) return null;
  final match = RegExp(r'aipms-google-binding=([^;,\s]+)').firstMatch(raw);
  return match == null ? null : 'aipms-google-binding=${match.group(1)}';
}

/// Platform-injectable Google ID token provider for native/web & tests.
abstract class GoogleIdTokenProvider {
  Future<String> obtainIdToken({
    required String clientId,
    required String nonce,
  });
}

/// Default provider backed by official `google_sign_in` 7.2.0.
class PlatformGoogleIdTokenProvider implements GoogleIdTokenProvider {
  PlatformGoogleIdTokenProvider();

  bool _initialized = false;

  @override
  Future<String> obtainIdToken({
    required String clientId,
    required String nonce,
  }) async {
    final signIn = GoogleSignIn.instance;
    try {
      if (!_initialized) {
        await signIn.initialize(
          clientId: kIsWeb ? clientId : null,
          serverClientId: kIsWeb ? null : clientId,
          nonce: nonce,
        );
        _initialized = true;
      }
      if (!signIn.supportsAuthenticate()) {
        final light = signIn.attemptLightweightAuthentication();
        final account = light == null ? null : await light;
        final token = account?.authentication.idToken;
        if (token == null || token.isEmpty) {
          throw const ApiException(
            'Trình duyệt hiện chưa hỗ trợ hộp thoại Google trực tiếp. Hãy dùng ứng dụng Android/iOS hoặc đăng nhập bằng email và mật khẩu.',
          );
        }
        return token;
      }
      final account = await signIn.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const ApiException('Không lấy được mã xác thực từ Google.');
      }
      return token;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const ApiException('Bạn đã hủy đăng nhập bằng Google.');
      }
      throw const ApiException(
        'Chưa kết nối được dịch vụ đăng nhập Google trên thiết bị này. Bạn có thể đăng nhập bằng mật khẩu.',
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'Chưa thể khởi tạo đăng nhập Google. Vui lòng thử lại hoặc đăng nhập bằng mật khẩu.',
      );
    }
  }
}

String googleAuthErrorMessage(Object error) {
  if (error is ApiException) {
    return switch (error.statusCode) {
      403 => 'Nguồn truy cập này chưa được cấu hình cho đăng nhập Google. Vui lòng đăng nhập bằng mật khẩu.',
      401 => 'Chưa thể đăng nhập bằng tài khoản Google này. Nếu chưa liên kết, hãy đăng nhập bằng mật khẩu rồi liên kết Google trong tài khoản.',
      409 => 'Tài khoản Google này đã được liên kết với tài khoản khác.',
      429 => 'Bạn đã thử nhiều lần. Chờ một chút rồi thử lại.',
      503 => 'Dịch vụ đăng nhập Google tạm thời chưa sẵn sàng. Bạn có thể đăng nhập bằng mật khẩu.',
      _ => error.message,
    };
  }
  return 'Chưa kết nối được với dịch vụ đăng nhập Google. Bạn có thể đăng nhập bằng mật khẩu hoặc thử lại.';
}
