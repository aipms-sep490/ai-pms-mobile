import 'dart:convert';

import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/core/refresh_token_store.dart';
import 'package:ai_pms_mobile/features/auth/auth_controller.dart';
import 'package:ai_pms_mobile/features/ai/ai_screen.dart';
import 'package:ai_pms_mobile/features/workspace/task_editor_screen.dart';
import 'package:ai_pms_mobile/ui/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'support/mobile_fixtures.dart';

const _project = {
  'id': 1,
  'teamId': 3,
  'title': 'Đồ án liên ngành',
  'status': 'ACTIVE',
  'academicScopeProvenance': 'FROZEN_REGISTRATION_SNAPSHOT',
  'academicScope': {
    'projectMode': 'INTERDISCIPLINARY',
    'requirements': [
      {'majorId': 10},
      {'majorId': 20},
    ],
  },
  'majors': [
    {'majorId': 10, 'majorName': 'Ngành SE'},
    {'majorId': 20, 'majorName': 'Ngành MKT'},
  ],
};
const _requirements = {
  'requirements': [
    {'majorId': 10},
    {'majorId': 20},
  ],
};
Map<String, Object?> _cap({
  bool project = false,
  String version = 'version-1',
}) => {
  'resourceType': project ? 'PROJECT' : 'TASK',
  'resourceId': project ? 1 : 12,
  'projectId': 1,
  'projectStatus': 'ACTIVE',
  'resourceStatus': project ? 'ACTIVE' : 'TODO',
  'concurrencyToken': version,
  'actions': [
    for (final code in ['create_task', 'update_task', 'assign_task'])
      {'code': code, 'allowed': true, 'reasons': []},
  ],
};

Future<AuthController> _auth(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler,
) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api = ApiClient(
    origin: 'https://api.example.test',
    client: MockClient((r) async {
      if (r.url.path.endsWith('/login')) return json(loginFixture());
      if (r.url.path.endsWith('/me')) return json(user);
      return handler(r);
    }),
  );
  final auth = AuthController(api: api, storage: MemoryRefreshTokenStore());
  addTearDown(auth.dispose);
  addTearDown(api.close);
  await auth.signIn(user['email'] as String, 'fixture');
  return auth;
}

Future<void> _open(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            child: const Text('Mở trình soạn'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => screen),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Mở trình soạn'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('task creation accepts only unique frozen academic majors', () {
    expect(taskCreationMajors(_project, _requirements).map((r) => r['id']), [
      10,
      20,
    ]);
    for (final requirements in [
      {
        'requirements': [
          {'majorId': 99},
        ],
      },
      {
        'requirements': [
          {'majorId': 10},
          {'majorId': 10},
        ],
      },
    ]) {
      expect(
        () => taskCreationMajors(_project, requirements),
        throwsA(isA<ApiException>()),
      );
    }
    expect(
      () => taskCreationMajors({
        ..._project,
        'academicScopeProvenance': 'UNKNOWN',
      }, _requirements),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets(
    'AI task draft needs a primary major and creates one scoped task with UTC deadline',
    (tester) async {
      var writes = 0;
      final auth = await _auth(tester, (r) async {
        if (r.url.path == '/api/v1/tasks' && r.method == 'POST') {
          writes++;
          final body = jsonDecode(r.body) as Map;
          expect(body['milestoneId'], 2);
          expect(body['assigneeUserIds'], [17]);
          expect(body['parentTaskId'], isNull);
          expect(body['dueAt'], '2026-12-01T10:00:00.000Z');
          expect(body['disciplines'], [
            {'majorId': 10, 'role': 'PRIMARY'},
          ]);
          return json({...taskFixture(), 'id': 13}, 201);
        }
        if (r.url.path == '/api/v1/projects/1') return json(_project);
        if (r.url.path.endsWith('/execution-actions')) {
          return json(_cap(project: true));
        }
        if (r.url.path.endsWith('/major-requirements')) {
          return json(_requirements);
        }
        if (r.url.path == '/api/v1/milestones/project/1') {
          return json([
            {'id': 2, 'projectId': 1, 'title': 'Mốc khảo sát'},
          ]);
        }
        if (r.url.path == '/api/v1/teams/3') {
          return json({
            'members': [
              {'userId': 17, 'fullName': 'Sinh viên kiểm thử'},
            ],
          });
        }
        return json({}, 404);
      });
      await _open(
        tester,
        TaskEditorScreen(
          auth: auth,
          projectId: 1,
          initialDraft: const {
            'kind': 'TASK',
            'title': 'Kiểm tra API',
            'description': 'Mô tả nháp',
            'task': {
              'milestoneTitle': 'Mốc khảo sát',
              'assigneeNames': ['Sinh viên kiểm thử'],
              'dueAt': '2026-12-01T17:00:00+07:00',
            },
          },
        ),
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Tạo công việc'));
      expect(writes, 0);
      expect(find.text('Chọn một ngành chính.'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('major/null')));
      await _tap(tester, find.text('Ngành SE').last);
      await _tap(tester, find.widgetWithText(FilledButton, 'Tạo công việc'));
      expect(writes, 1);
      expect(find.text('Mở trình soạn'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edit conflict keeps draft, reloads authority and preserves parent and assignment fields',
    (tester) async {
      var version = 'version-1';
      var writes = 0;
      var denied = false;
      final auth = await _auth(tester, (r) async {
        if (r.url.path == '/api/v1/projects/1') return json(_project);
        if (r.url.path.endsWith('/execution-actions')) {
          if (denied) return json({}, 403);
          return json(_cap(version: version));
        }
        if (r.url.path == '/api/v1/milestones/project/1') {
          return json([
            {'id': 2, 'projectId': 1, 'title': 'Mốc khảo sát'},
          ]);
        }
        if (r.url.path == '/api/v1/tasks/12' && r.method == 'GET') {
          return json({
            ...taskFixture(token: version),
            'parentTaskId': 9,
            'title': version == 'version-1' ? 'Tên ban đầu' : 'Tên trên web',
          });
        }
        if (r.url.path == '/api/v1/tasks/12' && r.method == 'PUT') {
          writes++;
          final body = jsonDecode(r.body) as Map;
          expect(body['title'], 'Bản mobile đang soạn');
          expect(body['parentTaskId'], 9);
          expect(body.containsKey('assigneeUserIds'), isFalse);
          expect(body.containsKey('disciplines'), isFalse);
          expect(body['concurrencyToken'], version);
          if (writes == 1) {
            version = 'version-2';
            return json({}, 409);
          }
          return json(taskFixture(token: 'version-3'));
        }
        return json({}, 404);
      });
      await _open(
        tester,
        TaskEditorScreen(auth: auth, projectId: 1, taskId: 12),
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'Bản mobile đang soạn',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Lưu nội dung'));
      expect(writes, 1);
      expect(
        find.widgetWithText(TextFormField, 'Bản mobile đang soạn'),
        findsOneWidget,
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Tải dữ liệu mới'));
      expect(
        find.widgetWithText(TextFormField, 'Bản mobile đang soạn'),
        findsOneWidget,
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Lưu nội dung'));
      expect(writes, 2);
      expect(find.text('Mở trình soạn'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _open(
        tester,
        TaskEditorScreen(auth: auth, projectId: 1, taskId: 12),
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'Bản đang soạn trước khi mất quyền',
      );
      denied = true;
      await _tap(tester, find.widgetWithText(FilledButton, 'Lưu nội dung'));
      expect(writes, 2);
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'progress assistant sends the explicit grounded tool and reads persisted result',
    (tester) async {
      var asks = 0;
      const response = {
        'answer': 'Có một công việc quá hạn.',
        'generationStatus': 'COMPLETED',
        'citations': [],
        'projectEvidence': [],
      };
      final auth = await _auth(tester, (r) async {
        if (r.url.path == '/api/v1/academic/assistant/conversations' &&
            r.method == 'POST') {
          return json({'id': 8, 'revision': 0, 'scope': 'COMBINED'});
        }
        if (r.url.path == '/api/v1/academic/assistant/ask') {
          asks++;
          final body = jsonDecode(r.body) as Map;
          expect(body['toolMode'], 'PROGRESS');
          expect(body['scope'], 'COMBINED');
          expect(body['expectedRevision'], 0);
          expect(body['projectId'], 1);
          return json(response);
        }
        if (r.url.path.endsWith('/conversations/8')) {
          return json({
            'conversation': {'revision': 1, 'scope': 'COMBINED'},
            'turns': [
              {'id': 9, 'query': 'Tiến độ', 'response': response},
            ],
            'hasMore': false,
          });
        }
        return json({}, 404);
      });
      await _open(tester, AssistantChatScreen(auth: auth, projectId: 1));
      await _tap(tester, find.byTooltip('Tùy chọn'));
      await _tap(tester, find.text('Tiến độ'));
      await _tap(tester, find.text('Áp dụng'));
      await _tap(tester, find.byTooltip('Xem tiến độ'));
      expect(asks, 1);
      expect(find.text('Có một công việc quá hạn.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
