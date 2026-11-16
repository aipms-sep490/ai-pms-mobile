import 'dart:convert';

import 'package:http/http.dart' as http;

const user = {
  'id': 17,
  'email': 'mobile-smoke@example.test',
  'fullName': 'Sinh viên kiểm thử',
  'roles': ['STUDENT'],
};

Map<String, Object?> dashboard() => {
  'asOfUtc': DateTime.now().toUtc().toIso8601String(),
  'context': {
    'selectedSemester': {'name': 'Học kỳ FA26'},
    'currentTeam': {'name': 'Nhóm SE28', 'isLeader': true},
  },
  'project': {
    'id': 1,
    'code': 'SE28',
    'title': 'Hệ thống quản lý tiến trình đồ án',
    'status': 'ACTIVE',
    'supervisor': {'name': 'Giảng viên hướng dẫn'},
    'analysis': {
      'dataStatus': 'SUFFICIENT',
      'riskLevel': 'LOW',
      'progressSummary': {'progressPercentage': 62},
    },
  },
  'unreadNotifications': 3,
  'assignedOpenTasks': 5,
  'assignedOverdueTasks': 1,
  'taskDeadlines': [
    {
      'id': 12,
      'title': 'Hoàn thiện tài liệu thiết kế',
      'status': 'IN_PROGRESS',
      'dueAtUtc': '2026-11-15T10:00:00Z',
      'isOverdue': false,
    },
  ],
  'milestoneDeadlines': [],
};

http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> loginFixture() => {
  'accessToken': 'fixture-access',
  'refreshToken': 'fixture-refresh',
  'tokenType': 'Bearer',
  'expiresAtUtc': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String(),
  'refreshTokenExpiresAtUtc': DateTime.now()
      .toUtc()
      .add(const Duration(days: 1))
      .toIso8601String(),
  'user': user,
};

Map<String, Object?> taskFixture({
  String status = 'TODO',
  String token = 'version-1',
}) => {
  'id': 12,
  'milestoneId': 2,
  'title': 'Công việc thử nghiệm',
  'description': 'Nội dung đầy đủ của công việc.',
  'status': status,
  'priority': 'HIGH',
  'dueAt': '2026-11-15T10:00:00Z',
  'concurrencyToken': token,
  'assignees': [
    {'userId': 17, 'userFullName': 'Sinh viên kiểm thử'},
  ],
  'dependencies': [],
};

Map<String, Object?> capabilityFixture({
  String status = 'TODO',
  String token = 'version-1',
  bool allowed = true,
}) => {
  'resourceType': 'TASK',
  'resourceId': 12,
  'projectId': 1,
  'resourceStatus': status,
  'concurrencyToken': token,
  'actions': [
    {'code': 'change_task_status', 'allowed': allowed, 'reasons': []},
  ],
};

Map<String, Object?> pageFixture(
  List<Object?> items, {
  int page = 1,
  int pages = 1,
  int? total,
}) => {
  'items': items,
  'page': page,
  'pageSize': 20,
  'totalPages': pages,
  'totalCount': total ?? items.length,
};
