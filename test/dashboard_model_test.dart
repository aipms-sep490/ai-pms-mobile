import 'package:ai_pms_mobile/features/dashboard/dashboard_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> dashboardJson() => {
  'asOfUtc': '2026-11-14T07:00:00Z',
  'context': {'selectedSemester': null, 'currentTeam': null},
  'project': null,
  'unreadNotifications': 0,
  'assignedOpenTasks': 0,
  'assignedOverdueTasks': 0,
  'taskDeadlines': <Object?>[],
  'milestoneDeadlines': <Object?>[],
};

void main() {
  test('overdue ordering follows server flags instead of the phone clock', () {
    final json = dashboardJson();
    json['taskDeadlines'] = [
      {
        'id': 1,
        'title': 'Old but not flagged',
        'status': 'TODO',
        'dueAtUtc': '2000-01-01T00:00:00Z',
        'isOverdue': false,
      },
      {
        'id': 2,
        'title': 'Flagged by server',
        'status': 'TODO',
        'dueAtUtc': '2099-01-01T00:00:00Z',
        'isOverdue': true,
      },
    ];
    json['milestoneDeadlines'] = [
      {
        'id': 1,
        'title': 'Milestone',
        'status': 'OPEN',
        'dueDate': '2026-11-14',
        'isOverdue': false,
      },
    ];
    final dashboard = StudentDashboard.fromJson(json);
    expect(dashboard.deadlines.map((deadline) => deadline.key), [
      'task-2',
      'task-1',
      'milestone-1',
    ]);
    expect(dashboard.deadlines.last.formattedDue, '14/11/2026');
  });

  test('UTC deadlines cross midnight in Vietnam without shifting DateOnly', () {
    expect(
      formatVietnamTime(DateTime.parse('2026-11-13T18:00:00Z')),
      '14/11 01:00',
    );
    expect(
      formatVietnamTime(parseUtcTimestamp('2026-11-13T18:00:00')!),
      '14/11 01:00',
    );
    expect(
      formatVietnamTime(DateTime.parse('2026-11-14T01:00:00+07:00')),
      '14/11 01:00',
    );
    expect(parseUtcTimestamp('invalid'), isNull);
  });

  test('missing or insufficient progress remains unknown instead of zero', () {
    final json = dashboardJson();
    expect(StudentDashboard.fromJson(json).project, isNull);
    final project = <String, dynamic>{
      'id': 1,
      'code': 'P1',
      'title': 'Project',
      'status': 'ACTIVE',
      'supervisor': null,
      'analysis': {
        'dataStatus': 'INSUFFICIENT_DATA',
        'progressSummary': {'progressPercentage': 0},
      },
    };
    json['project'] = project;
    expect(StudentDashboard.fromJson(json).project!.progressPercentage, isNull);
    project['analysis'] = {
      'dataStatus': 'SUFFICIENT',
      'progressSummary': {'progressPercentage': 42.5},
    };
    expect(StudentDashboard.fromJson(json).project!.progressPercentage, 42.5);
    project['analysis'] = {
      'dataStatus': 'SUFFICIENT',
      'progressSummary': {'progressPercentage': 120},
    };
    expect(StudentDashboard.fromJson(json).project!.progressPercentage, 100);
  });

  test(
    'incomplete metric payload is rejected instead of inventing zero counts',
    () {
      final json = dashboardJson()..remove('assignedOpenTasks');
      expect(() => StudentDashboard.fromJson(json), throwsFormatException);
    },
  );
}
