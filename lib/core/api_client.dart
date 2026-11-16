import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode = 0});

  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required String origin,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _origin = origin.trim(),
       _client = client ?? http.Client();

  final String _origin;
  final http.Client _client;
  final Duration timeout;

  Uri _requestUri(String path) {
    final base = Uri.tryParse(_origin);
    if (base == null ||
        !['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        (base.path.isNotEmpty && base.path != '/') ||
        base.hasQuery ||
        base.hasFragment) {
      throw const ApiException(
        'Chưa cấu hình địa chỉ API hợp lệ. Kiểm tra API_BASE_URL.',
      );
    }
    final relative = Uri.tryParse(path);
    if (relative == null ||
        !path.startsWith('/api/v1/') ||
        relative.hasScheme ||
        relative.hasAuthority ||
        relative.hasFragment ||
        path.contains('\\') ||
        _hasUnsafeSegments(path) ||
        relative.pathSegments.any(
          (part) =>
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains('\\'),
        )) {
      throw const ApiException('Đường dẫn API không hợp lệ.');
    }
    final resolved = base.resolveUri(relative);
    if (resolved.origin != base.origin ||
        !resolved.path.startsWith('/api/v1/')) {
      throw const ApiException('Đường dẫn API không hợp lệ.');
    }
    return resolved;
  }

  Future<Object?> request(
    String path, {
    String method = 'GET',
    Map<String, String>? headers,
    Object? body,
  }) async {
    final uri = _requestUri(path);
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll({'Accept': 'application/json', ...?headers});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await (() async {
        final stream = await _client.send(request);
        return http.Response.fromStream(stream);
      })().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Server ProblemDetails may contain private provider/database details.
        String? safeMessage;
        if (response.statusCode == 409) {
          try {
            final problem = jsonDecode(utf8.decode(response.bodyBytes));
            if (problem is Map<String, dynamic>) {
              safeMessage = switch (problem['code'] ?? problem['errorCode']) {
                'TASK_DEPENDENCY_BLOCKED' => 'Công việc còn phụ thuộc chưa hoàn tất. Kiểm tra các việc phụ thuộc trước khi tiếp tục.',
                'PROJECT_NOT_ACTIVE' =>
                  'Đồ án hiện không cho phép cập nhật công việc.',
                _ => null,
              };
            }
          } on FormatException {
            // Use the safe status message for non-JSON errors.
          }
        }
        throw ApiException(
          safeMessage ?? _statusMessage(response.statusCode),
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 204 || response.bodyBytes.isEmpty) return null;
      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw const ApiException('Phản hồi từ máy chủ không hợp lệ.');
      }
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('Kết nối quá thời gian chờ. Vui lòng thử lại.');
    } catch (_) {
      throw const ApiException(
        'Không kết nối được máy chủ. Kiểm tra mạng và thử lại.',
      );
    }
  }

  void close() => _client.close();
}

bool _hasUnsafeSegments(String path) {
  try {
    // Uri.parse normalizes dot segments, so inspect the original path first.
    return path.split('?').first.split('/').any((segment) {
      final decoded = Uri.decodeComponent(segment);
      return decoded == '.' ||
          decoded == '..' ||
          decoded.contains('/') ||
          decoded.contains('\\');
    });
  } on FormatException {
    return true;
  }
}

String _statusMessage(int status) => switch (status) {
  400 => 'Thông tin chưa hợp lệ. Vui lòng kiểm tra và thử lại.',
  401 => 'Thông tin đăng nhập không hợp lệ hoặc phiên đăng nhập đã hết hạn.',
  403 => 'Tài khoản không được phép thực hiện thao tác này.',
  404 => 'Không tìm thấy dữ liệu được yêu cầu.',
  409 => 'Dữ liệu đã thay đổi. Vui lòng tải lại trước khi tiếp tục.',
  422 => 'Thao tác chưa đáp ứng điều kiện của hệ thống.',
  429 => 'Có quá nhiều yêu cầu. Vui lòng thử lại sau ít phút.',
  _ => 'Hệ thống chưa thể xử lý yêu cầu. Vui lòng thử lại.',
};
