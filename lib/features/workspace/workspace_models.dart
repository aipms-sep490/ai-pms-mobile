import '../../core/api_client.dart';
import '../dashboard/dashboard_model.dart';

typedef Json = Map<String, dynamic>;

Json objectOf(Object? value) {
  if (value is! Json) throw const FormatException('Invalid object');
  return value;
}

List<Json> recordsOf(Object? value) {
  if (value is! List) throw const FormatException('Invalid list');
  return value.map(objectOf).toList();
}

int idOf(Json value, [String key = 'id']) {
  final id = value[key];
  if (id is! int || id <= 0) throw const FormatException('Invalid id');
  return id;
}

String textOf(Json value, String key, [String fallback = '—']) =>
    value[key] is String && (value[key] as String).trim().isNotEmpty
    ? value[key] as String
    : fallback;

String displayDate(Object? value) {
  if (value is! String || value.isEmpty) return 'Chưa có thời gian';
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    final parts = value.split('-');
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }
  final date = parseUtcTimestamp(value)?.toLocal();
  if (date == null) return 'Chưa có thời gian';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} · ${two(date.hour)}:${two(date.minute)}';
}

String statusText(Object? value) => switch (value) {
  'SUBMITTED' => 'Đã nộp',
  'WEEKLY' => 'Báo cáo tuần',
  'MONTHLY' => 'Báo cáo tháng',
  'PENDING' || 'INVITED' => 'Đang chờ',
  'ACCEPTED' => 'Đã chấp nhận',
  'REJECTED' || 'DECLINED' => 'Đã từ chối',
  'EXPIRED' => 'Đã hết hạn',
  'TENTATIVE' => 'Chưa chắc chắn',
  'SCHEDULED' => 'Đã lên lịch',
  'REVIEWED' => 'Đã phản hồi',
  'LOW' => 'Thấp',
  'MEDIUM' => 'Trung bình',
  'HIGH' => 'Cao',
  'CRITICAL' => 'Khẩn cấp',
  _ => dashboardStatusLabel(value is String ? value : '—'),
};

// Mirrors the backend TaskStateMachine; the capability gate and mutation API
// remain authoritative. Unknown states expose no mutation.
List<String> taskTransitions(String status) =>
    const {
      'TODO': ['IN_PROGRESS', 'BLOCKED', 'CANCELLED'],
      'IN_PROGRESS': ['TODO', 'BLOCKED', 'IN_REVIEW', 'DONE', 'CANCELLED'],
      'BLOCKED': ['TODO', 'IN_PROGRESS', 'CANCELLED'],
      'IN_REVIEW': ['IN_PROGRESS', 'DONE', 'CANCELLED'],
      'DONE': ['IN_PROGRESS', 'CANCELLED'],
      'CANCELLED': ['TODO'],
    }[status] ??
    <String>[];

class PageData {
  const PageData(this.items, this.page, this.totalPages, this.totalCount);
  final List<Json> items;
  final int page;
  final int totalPages;
  final int totalCount;

  factory PageData.fromJson(Object? value) {
    final json = objectOf(value);
    final items = recordsOf(json['items']);
    for (final item in items) {
      idOf(item);
    }
    final page = json['page'];
    final totalPages = json['totalPages'];
    final totalCount = json['totalCount'];
    if (page is! int ||
        page < 1 ||
        totalPages is! int ||
        totalPages < 0 ||
        totalCount is! int ||
        totalCount < 0) {
      throw const FormatException('Invalid pagination');
    }
    return PageData(items, page, totalPages, totalCount);
  }
}

class TaskAccess {
  TaskAccess(this.task, this.capability) {
    recordsOf(task['assignees']);
    recordsOf(task['dependencies']);
    recordsOf(capability['actions']);
    if (capability['resourceType'] != 'TASK' ||
        idOf(capability, 'resourceId') != idOf(task)) {
      throw const FormatException('Invalid task capability');
    }
  }
  final Json task;
  final Json capability;

  String get token => textOf(capability, 'concurrencyToken', '');
  bool get canChange => allows('change_task_status');
  bool allows(String code) =>
      token.isNotEmpty &&
      textOf(task, 'concurrencyToken', '').replaceAll('-', '') ==
          token.replaceAll('-', '') &&
      task['status'] == capability['resourceStatus'] &&
      recordsOf(capability['actions'])
          .any((action) => action['code'] == code && action['allowed'] == true);
}

bool executionAllowed(
  Json capability, {
  required String type,
  required int id,
  required int projectId,
  required String action,
}) =>
    capability['resourceType'] == type &&
    capability['resourceId'] == id &&
    capability['projectId'] == projectId &&
    capability['projectStatus'] == 'ACTIVE' &&
    recordsOf(capability['actions'])
        .any((row) => row['code'] == action && row['allowed'] == true);

Uri? externalUri(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
          ['http', 'https'].contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

String errorText(Object error) => error is ApiException
    ? error.message
    : 'Không thể đọc dữ liệu. Vui lòng thử lại.';

class EntityTarget {
  const EntityTarget(this.type, this.id);
  final String type;
  final int id;

  static EntityTarget? fromNotification(Json json) {
    final id = json['relatedEntityId'];
    final type = json['relatedEntityType'];
    if (id is! int || id <= 0 || type is! String) return null;
    return const {
          'TASK',
          'PROJECT',
          'MILESTONE',
          'MEETING',
          'PROGRESS_REPORT',
          'TEAM_INVITATION',
          'TEAM',
        }.contains(type.toUpperCase())
        ? EntityTarget(type.toUpperCase(), id)
        : null;
  }
}
