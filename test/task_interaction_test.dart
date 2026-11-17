import 'dart:async';

import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/core/refresh_token_store.dart';
import 'package:ai_pms_mobile/features/auth/auth_controller.dart';
import 'package:ai_pms_mobile/features/meetings/video_meeting_screen.dart';
import 'package:ai_pms_mobile/features/workspace/task_editor_screen.dart';
import 'package:ai_pms_mobile/features/workspace/tasks_screen.dart';
import 'package:ai_pms_mobile/ui/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'support/mobile_fixtures.dart';

const _createCapability = {
  'resourceType': 'PROJECT',
  'resourceId': 1,
  'projectId': 1,
  'projectStatus': 'ACTIVE',
  'actions': [
    {'code': 'create_task', 'allowed': true, 'reasons': []},
  ],
};
const _project = {
  'id': 1,
  'teamId': 3,
  'status': 'ACTIVE',
  'title': 'Đồ án kiểm tra tương tác',
  'academicScopeProvenance': 'FROZEN_REGISTRATION_SNAPSHOT',
  'academicScope': {
    'projectMode': 'SINGLE_MAJOR',
    'requirements': [
      {'majorId': 10},
    ],
  },
  'majors': [
    {'majorId': 10, 'majorName': 'Kỹ thuật phần mềm'},
  ],
};
const _videoSession = {
  'session': {'status': 'LIVE'},
  'capabilities': {'canStart': false, 'canJoin': true, 'canEnd': false},
  'denialReasons': <String>[],
};

Future<AuthController> _auth(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handle,
) async {
  await tester.binding.setSurfaceSize(const Size(320, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api = ApiClient(
    origin: 'https://api.example.test',
    client: MockClient((request) async {
      if (request.url.path.endsWith('/login')) return json(loginFixture());
      if (request.url.path.endsWith('/me')) return json(user);
      expect(
        request.method,
        'GET',
        reason: 'Interaction fixtures never write.',
      );
      return handle(request);
    }),
  );
  final auth = AuthController(api: api, storage: MemoryRefreshTokenStore());
  addTearDown(auth.dispose);
  addTearDown(api.close);
  await auth.signIn(user['email'] as String, 'fixture');
  return auth;
}

Future<void> _show(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: screen,
    ),
  );
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('canceled back keeps an author draft at 320dp and 200%', (
    tester,
  ) async {
    final auth = await _auth(tester, (request) async {
      switch (request.url.path) {
        case '/api/v1/dashboards/student':
          return json(dashboard());
        case '/api/v1/tasks/project/1':
          return json(pageFixture([]));
        case '/api/v1/projects/1':
          return json(_project);
        case '/api/v1/projects/1/execution-actions':
          return json(_createCapability);
        case '/api/v1/projects/1/major-requirements':
          return json({
            'requirements': [
              {'majorId': 10},
            ],
          });
        case '/api/v1/milestones/project/1':
          return json([
            {'id': 2, 'projectId': 1, 'title': 'Mốc kiểm tra'},
          ]);
        case '/api/v1/teams/3':
          return json({'members': []});
        default:
          return json({}, 404);
      }
    });
    await _show(
      tester,
      Scaffold(
        body: TasksScreen(auth: auth, onChanged: () {}),
      ),
    );
    final create = find.widgetWithText(FilledButton, 'Tạo');
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditorScreen, skipOffstage: false), findsOneWidget);
    final title = find.byType(TextFormField).first;
    await tester.ensureVisible(title);
    await tester.enterText(title, 'Bản soạn cần giữ lại');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục soạn'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(title).controller!.text,
      'Bản soạn cần giữ lại',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bỏ bản soạn'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditorScreen, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed task search can clear filters and retain milestone scope',
    (tester) async {
      final queries = <Map<String, String>>[];
      final auth = await _auth(tester, (request) async {
        switch (request.url.path) {
          case '/api/v1/dashboards/student':
            return json(dashboard());
          case '/api/v1/milestones/5':
            return json({'id': 5, 'projectId': 1});
          case '/api/v1/tasks/project/1':
            queries.add(request.url.queryParameters);
            if (request.url.queryParameters['search'] == 'không tải được') {
              return json({}, 503);
            }
            return json(pageFixture([taskFixture()]));
          case '/api/v1/projects/1/execution-actions':
            return json(_createCapability);
          default:
            return json({}, 404);
        }
      });
      await _show(
        tester,
        Scaffold(
          body: TasksScreen(
            auth: auth,
            onChanged: () {},
            milestoneId: 5,
            showHeading: false,
          ),
        ),
      );
      final search = find.byType(TextField);
      await tester.ensureVisible(search);
      await tester.enterText(search, 'không tải được');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(queries.last['search'], 'không tải được');
      expect(find.byType(TextField), findsNothing);
      final clear = find.byKey(const Key('task-error-clear'));
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(queries.last['search'], isNull);
      expect(queries.last['milestoneId'], '5');
      expect(queries.last['assigneeUserId'], isNull);
      expect(queries.last['page'], '1');
      expect(find.text('Công việc thử nghiệm'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late video poll cannot restore controls after a newer denied refresh',
    (tester) async {
      var reads = 0;
      final oldPoll = Completer<http.Response>();
      final auth = await _auth(tester, (request) async {
        expect(request.url.path, '/api/v1/meetings/8/video/session');
        reads++;
        if (reads == 1) return json(_videoSession);
        if (reads == 2) return oldPoll.future;
        return json({}, 403);
      });
      await _show(tester, VideoMeetingScreen(auth: auth, meetingId: 8));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Tham gia phòng'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(reads, 2);
      await tester.tap(find.byTooltip('Cập nhật quyền tham gia'));
      await tester.pumpAndSettle();
      expect(reads, 3);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Chưa thể tham gia'),
            )
            .onPressed,
        isNull,
      );
      oldPoll.complete(json(_videoSession));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Tham gia phòng'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Chưa thể tham gia'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
