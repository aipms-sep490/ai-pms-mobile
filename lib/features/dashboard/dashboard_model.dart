class StudentDashboard {
  const StudentDashboard({
    required this.asOfUtc,
    required this.semesterName,
    required this.teamName,
    required this.project,
    required this.unreadNotifications,
    required this.assignedOpenTasks,
    required this.assignedOverdueTasks,
    required this.deadlines,
  });

  final DateTime asOfUtc;
  final String? semesterName;
  final String? teamName;
  final DashboardProject? project;
  final int unreadNotifications;
  final int assignedOpenTasks;
  final int assignedOverdueTasks;
  final List<DashboardDeadline> deadlines;

  factory StudentDashboard.fromJson(Map<String, dynamic> json) {
    final context = _object(json['context']);
    final semester = context['selectedSemester'];
    final team = context['currentTeam'];
    final timestamp = parseUtcTimestamp(_string(json['asOfUtc']));
    if (timestamp == null) {
      throw const FormatException('Invalid dashboard time.');
    }

    final deadlines = <DashboardDeadline>[
      ..._array(json['taskDeadlines']).map(
        (value) =>
            DashboardDeadline.fromJson(_object(value), isMilestone: false),
      ),
      ..._array(json['milestoneDeadlines']).map(
        (value) =>
            DashboardDeadline.fromJson(_object(value), isMilestone: true),
      ),
    ];
    // The API owns overdue status; the phone's clock must not change it.
    deadlines.sort((left, right) {
      if (left.isOverdue != right.isOverdue) return left.isOverdue ? -1 : 1;
      final order = left.sortTime.compareTo(right.sortTime);
      return order == 0 ? left.key.compareTo(right.key) : order;
    });

    return StudentDashboard(
      asOfUtc: timestamp,
      semesterName: semester == null
          ? null
          : _string(_object(semester)['name']),
      teamName: team == null ? null : _string(_object(team)['name']),
      project: json['project'] == null
          ? null
          : DashboardProject.fromJson(_object(json['project'])),
      unreadNotifications: _count(json['unreadNotifications']),
      assignedOpenTasks: _count(json['assignedOpenTasks']),
      assignedOverdueTasks: _count(json['assignedOverdueTasks']),
      deadlines: List.unmodifiable(deadlines),
    );
  }
}

class DashboardProject {
  const DashboardProject({
    required this.id,
    required this.code,
    required this.title,
    required this.status,
    required this.supervisorName,
    required this.progressPercentage,
  });

  final int id;
  final String code;
  final String title;
  final String status;
  final String? supervisorName;
  final double? progressPercentage;

  factory DashboardProject.fromJson(Map<String, dynamic> json) {
    final supervisor = json['supervisor'];
    final analysisValue = json['analysis'];
    double? progress;
    if (analysisValue != null) {
      final analysis = _object(analysisValue);
      if (analysis['dataStatus'] == 'SUFFICIENT') {
        final summary = _object(analysis['progressSummary']);
        final value = summary['progressPercentage'];
        if (value is num && value.isFinite) {
          progress = value.clamp(0, 100).toDouble();
        }
      }
    }
    return DashboardProject(
      id: _count(json['id']),
      code: _string(json['code']),
      title: _string(json['title']),
      status: _string(json['status']),
      supervisorName: supervisor == null
          ? null
          : _string(_object(supervisor)['name']),
      progressPercentage: progress,
    );
  }
}

class DashboardDeadline {
  const DashboardDeadline({
    required this.id,
    required this.isMilestone,
    required this.title,
    required this.status,
    required this.due,
    required this.isOverdue,
  });

  final int id;
  final bool isMilestone;
  final String title;
  final String status;
  final String due;
  final bool isOverdue;

  String get key => '${isMilestone ? 'milestone' : 'task'}-$id';

  factory DashboardDeadline.fromJson(
    Map<String, dynamic> json, {
    required bool isMilestone,
  }) {
    if (json['isOverdue'] is! bool) {
      throw const FormatException('Invalid deadline status.');
    }
    return DashboardDeadline(
      id: _count(json['id']),
      isMilestone: isMilestone,
      title: _string(json['title']),
      status: _string(json['status']),
      due: _string(json[isMilestone ? 'dueDate' : 'dueAtUtc']),
      isOverdue: json['isOverdue'] as bool,
    );
  }

  DateTime get sortTime {
    final date = isMilestone
        ? (_isDateOnly(due) ? DateTime.tryParse('${due}T23:59:59+07:00') : null)
        : parseUtcTimestamp(due);
    return date ?? DateTime.utc(9999);
  }

  String get formattedDue {
    if (isMilestone) {
      if (!_isDateOnly(due)) return 'Chưa xác định hạn';
      final parts = due.split('-');
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    }
    final date = parseUtcTimestamp(due);
    return date == null ? 'Chưa xác định hạn' : formatVietnamTime(date);
  }
}

DateTime? parseUtcTimestamp(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(value)) return null;
  // The contract calls these fields *Utc, including legacy timestamps without Z.
  final hasOffset = RegExp(
    r'(Z|[+-]\d{2}:\d{2})$',
    caseSensitive: false,
  ).hasMatch(value);
  return DateTime.tryParse(hasOffset ? value : '${value}Z')?.toUtc();
}

String formatVietnamTime(DateTime timestamp) {
  final date = timestamp.toUtc().add(const Duration(hours: 7));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)} ${two(date.hour)}:${two(date.minute)}';
}

String dashboardStatusLabel(String status) {
  const labels = <String, String>{
    'DRAFT': 'Bản nháp',
    'SUBMITTED': 'Đã nộp đề cương',
    'UNDERREVIEW': 'Đang thẩm định',
    'REVISIONREQUIRED': 'Cần chỉnh sửa',
    'REJECTED': 'Không được chấp thuận',
    'APPROVED': 'Đã phê duyệt',
    'SUPERVISORPENDING': 'Chờ phân công giảng viên',
    'ACTIVE': 'Đang thực hiện',
    'FINALSUBMISSION': 'Đang bàn giao',
    'COMPLETED': 'Đã hoàn thành',
    'ARCHIVED': 'Đã lưu trữ',
    'TODO': 'Cần thực hiện',
    'INPROGRESS': 'Đang thực hiện',
    'BLOCKED': 'Đang bị chặn',
    'INREVIEW': 'Chờ xem xét',
    'DONE': 'Đã hoàn thành',
    'CANCELLED': 'Đã hủy',
    'OPEN': 'Đang mở',
    'PLANNED': 'Đã lên kế hoạch',
  };
  return labels[status.replaceAll('_', '').toUpperCase()] ?? status;
}

bool _isDateOnly(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

Map<String, dynamic> _object(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const FormatException('Invalid dashboard object.');
}

List<dynamic> _array(Object? value) {
  if (value is List) return value;
  throw const FormatException('Invalid dashboard list.');
}

String _string(Object? value) {
  if (value is String) return value;
  throw const FormatException('Invalid dashboard text.');
}

int _count(Object? value) {
  if (value is int && value >= 0) return value;
  throw const FormatException('Invalid dashboard count.');
}
