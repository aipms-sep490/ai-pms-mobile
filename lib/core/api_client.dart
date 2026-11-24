import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode = 0, this.errorCode});

  final String message;
  final int statusCode;
  final String? errorCode;

  @override
  String toString() => message;
}

class ApiUpload {
  const ApiUpload(
    this.name,
    this.bytes, {
    this.field = 'File',
    this.contentType = 'application/octet-stream',
  });
  final String name;
  final Uint8List bytes;
  final String field;
  final String contentType;
}

class ApiResponseData {
  const ApiResponseData({
    required this.body,
    required this.headers,
    required this.statusCode,
  });

  final Object? body;
  final Map<String, String> headers;
  final int statusCode;
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

  String get origin => _origin;

  Uri validatedOrigin() {
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
    return base;
  }

  Uri _requestUri(String path, {bool allowHub = false}) {
    final base = validatedOrigin();
    final relative = Uri.tryParse(path);
    final validPrefix =
        path.startsWith('/api/v1/') || (allowHub && path.startsWith('/hubs/'));
    if (relative == null ||
        !validPrefix ||
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
    final validResolved =
        resolved.path.startsWith('/api/v1/') ||
        (allowHub && resolved.path.startsWith('/hubs/'));
    if (resolved.origin != base.origin || !validResolved) {
      throw const ApiException('Đường dẫn API không hợp lệ.');
    }
    return resolved;
  }

  http.BaseRequest _buildRequest(
    Uri uri, {
    required String method,
    Map<String, String>? headers,
    Object? body,
    ApiUpload? upload,
    List<ApiUpload> uploads = const [],
    String accept = 'application/json',
  }) {
    final allUploads = [?upload, ...uploads];
    final http.BaseRequest request;
    if (allUploads.isNotEmpty || accept == 'application/x-ndjson') {
      final multipart = http.MultipartRequest(method, uri);
      for (final file in allUploads) {
        multipart.files.add(
          http.MultipartFile.fromBytes(
            file.field,
            file.bytes,
            filename: file.name,
            contentType: http.MediaType.parse(file.contentType),
          ),
        );
      }
      if (body is Map<String, String>) multipart.fields.addAll(body);
      request = multipart;
    } else {
      final jsonRequest = http.Request(method, uri);
      if (body != null) {
        jsonRequest.headers['Content-Type'] = 'application/json';
        jsonRequest.body = jsonEncode(body);
      }
      request = jsonRequest;
    }
    request
      ..followRedirects = false
      ..headers.addAll({'Accept': accept, ...?headers});
    return request;
  }

  Future<Object?> request(
    String path, {
    String method = 'GET',
    Map<String, String>? headers,
    Object? body,
    Duration? requestTimeout,
    ApiUpload? upload,
    bool binary = false,
    bool allowHub = false,
  }) async {
    final result = await requestRaw(
      path,
      method: method,
      headers: headers,
      body: body,
      requestTimeout: requestTimeout,
      upload: upload,
      binary: binary,
      allowHub: allowHub,
    );
    return result.body;
  }

  Future<ApiResponseData> requestRaw(
    String path, {
    String method = 'GET',
    Map<String, String>? headers,
    Object? body,
    Duration? requestTimeout,
    ApiUpload? upload,
    bool binary = false,
    bool allowHub = false,
  }) async {
    final uri = _requestUri(path, allowHub: allowHub);
    final req = _buildRequest(
      uri,
      method: method,
      headers: headers,
      body: body,
      upload: upload,
    );
    try {
      final response = await (() async {
        final stream = await _client.send(req);
        return http.Response.fromStream(stream);
      })().timeout(requestTimeout ?? timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFromResponse(response.statusCode, response.bodyBytes);
      }
      if (response.statusCode == 204 || response.bodyBytes.isEmpty) {
        return ApiResponseData(
          body: null,
          headers: response.headers,
          statusCode: response.statusCode,
        );
      }
      if (binary) {
        return ApiResponseData(
          body: response.bodyBytes,
          headers: response.headers,
          statusCode: response.statusCode,
        );
      }
      try {
        return ApiResponseData(
          body: jsonDecode(utf8.decode(response.bodyBytes)),
          headers: response.headers,
          statusCode: response.statusCode,
        );
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

  /// Sends a multipart NDJSON streaming request (used by AI Assistant V4).
  Stream<String> requestNdjsonStream(
    String path, {
    String method = 'POST',
    Map<String, String>? headers,
    Map<String, String>? fields,
    List<ApiUpload> uploads = const [],
    Duration? requestTimeout,
  }) async* {
    final uri = _requestUri(path);
    final req = _buildRequest(
      uri,
      method: method,
      headers: headers,
      body: fields,
      uploads: uploads,
      accept: 'application/x-ndjson',
    );
    final http.StreamedResponse response;
    try {
      response = await _client
          .send(req)
          .timeout(requestTimeout ?? const Duration(seconds: 90));
    } on TimeoutException {
      throw const ApiException('Kết nối quá thời gian chờ. Vui lòng thử lại.');
    } catch (_) {
      throw const ApiException(
        'Không kết nối được máy chủ. Kiểm tra mạng và thử lại.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final bytes = await response.stream.toBytes();
      throw _errorFromResponse(response.statusCode, bytes);
    }
    try {
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) yield trimmed;
      }
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('Kết nối quá thời gian chờ. Vui lòng thử lại.');
    } catch (_) {
      throw const ApiException(
        'Kết nối bị gián đoạn trong khi nhận phản hồi. Mở lại lịch sử để kiểm tra.',
      );
    }
  }

  void close() => _client.close();
}

ApiException _errorFromResponse(int statusCode, Uint8List bodyBytes) {
  // Server ProblemDetails may contain private provider/database details.
  // Only map explicit, safe workflow error codes.
  String? code;
  String? safeMessage;
  if (statusCode == 409 || statusCode == 422 || statusCode == 400) {
    try {
      final problem = jsonDecode(utf8.decode(bodyBytes));
      if (problem is Map<String, dynamic>) {
        final rawCode = problem['code'] ?? problem['errorCode'];
        if (rawCode is String && rawCode.trim().isNotEmpty) {
          code = rawCode.trim().toUpperCase();
        }
        safeMessage = switch (code) {
          'TASK_DEPENDENCY_BLOCKED' => 'Công việc còn phụ thuộc chưa hoàn tất. Kiểm tra các việc phụ thuộc trước khi tiếp tục.',
          'TASK_DEPENDENCY_IMPACT_PENDING' => 'Cần rà soát ảnh hưởng phụ thuộc của công việc trước khi chuyển trạng thái.',
          'PROJECT_NOT_ACTIVE' =>
            'Đồ án hiện không cho phép thực hiện thao tác này.',
          'BLOCKER_REASON_TOO_SHORT' => 'Lý do bị chặn cần tối thiểu 15 ký tự để nhóm và giảng viên nắm rõ vướng mắc.',
          'EVIDENCE_REQUIRED' => 'Công việc gắn mốc kiểm tra cần có ít nhất một minh chứng hợp lệ (READY) trước khi chuyển sang Hoàn thành.',
          'INVALID_INITIAL_STATUS' =>
            'Trạng thái khởi tạo chỉ cho phép Cần làm hoặc Đang làm.',
          'REPORT_LOCKED' =>
            'Báo cáo tiến độ đã bị khóa và không thể chỉnh sửa.',
          'PEER_EVAL_REASON_TOO_SHORT' || 'PEER_EVALUATION_COMMENT_REQUIRED' =>
            'Mức đánh giá dưới 50% cần ghi lý do rõ ràng (tối thiểu 30 ký tự).',
          'RESTORE_WINDOW_EXPIRED' =>
            'Đã quá thời gian hoàn tác xóa công việc.',
          _ => null,
        };
      }
    } on FormatException {
      // Use the safe status message for non-JSON errors.
    }
  }
  return ApiException(
    safeMessage ?? _statusMessage(statusCode),
    statusCode: statusCode,
    errorCode: code,
  );
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
  413 => 'Tệp vượt quá dung lượng cho phép.',
  _ => 'Hệ thống chưa thể xử lý yêu cầu. Vui lòng thử lại.',
};
