import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsAction;

import 'package:ai_pms_mobile/app.dart';
import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/core/refresh_token_store.dart';
import 'package:ai_pms_mobile/features/auth/auth_controller.dart';
import 'package:ai_pms_mobile/features/auth/sign_in_screen.dart';
import 'package:ai_pms_mobile/features/workspace/activity_screen.dart';
import 'package:ai_pms_mobile/features/workspace/tasks_screen.dart';
import 'package:ai_pms_mobile/ui/remote_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'support/mobile_fixtures.dart';

Future<AuthController> startApp(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handle,
) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api = ApiClient(
    origin: 'https://api.example.test',
    client: MockClient((request) async {
      switch (request.url.path) {
        case '/api/v1/auth/login':
          return json(loginFixture());
        case '/api/v1/auth/me':
          return json(user);
        case '/api/v1/auth/logout':
          return http.Response('', 204);
        case '/api/v1/dashboards/student':
          return json(dashboard());
        default:
          return handle(request);
      }
    }),
  );
  final auth = AuthController(api: api, storage: MemoryRefreshTokenStore());
  addTearDown(auth.dispose);
  addTearDown(api.close);
  await auth.signIn(user['email'] as String, 'fixture-password');
  await tester.pumpWidget(AiPmsApp(auth: auth));
  await tester.pumpAndSettle();
  return auth;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a returned detail route cannot refresh a disposed page', (
    tester,
  ) async {
    Future<void> Function()? refresh;
    await tester.pumpWidget(
      MaterialApp(
        home: RemotePage<int>(
          title: 'Test',
          load: () async => 1,
          content: (_, value, reload) {
            refresh = reload;
            return [Text('$value')];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await refresh!();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'task conflict reloads authority, blocked needs reason, writes cannot duplicate and logout closes detail',
    (tester) async {
      var token = 'version-1';
      var status = 'TODO';
      var writes = 0;
      var denied = false;
      var unavailable = false;
      final pending = Completer<http.Response>();
      final auth = await startApp(tester, (request) async {
        final path = request.url.path;
        if (path == '/api/v1/tasks/project/1') {
          expect(request.url.queryParameters['assigneeUserId'], '17');
          return json(pageFixture([taskFixture(status: status, token: token)]));
        }
        if (path == '/api/v1/tasks/12/status') {
          writes++;
          final body = jsonDecode(request.body) as Map;
          expect(request.method, 'PUT');
          if (writes == 1) {
            expect(body['concurrencyToken'], 'version-1');
            token = 'version-2';
            return json({
              'code': 'STALE_CONCURRENCY_TOKEN',
              'detail': 'private',
            }, 409);
          }
          expect(body['concurrencyToken'], 'version-2');
          expect(body['newStatus'], 'BLOCKED');
          expect(body['reason'], 'Chờ đầu vào từ nhóm thiết kế');
          return pending.future;
        }
        if (denied) return json({}, 403);
        if (unavailable) return json({}, 503);
        if (path == '/api/v1/tasks/12') {
          return json(taskFixture(status: status, token: token));
        }
        if (path == '/api/v1/projects/1/execution-actions') {
          return json({
            'resourceType': 'PROJECT',
            'resourceId': 1,
            'projectId': 1,
            'projectStatus': 'ACTIVE',
            'actions': [
              {
                'code': 'create_task',
                'allowed': false,
                'reasons': ['PROJECT_MANAGER_REQUIRED'],
              },
            ],
          });
        }
        if (path.endsWith('/execution-actions')) {
          return json(capabilityFixture(status: status, token: token));
        }
        if (path.endsWith('/history')) return json([]);
        return json({}, 404);
      });
      await tap(tester, find.text('Công việc').last);
      final searchSemantics = tester.ensureSemantics();
      try {
        await tester.pump();
        expect(find.bySemanticsLabel('Tìm công việc'), findsOneWidget);
      } finally {
        searchSemantics.dispose();
      }
      await tap(tester, find.text('Công việc thử nghiệm').last);
      await tap(tester, find.text('Đổi trạng thái'));
      await tap(tester, find.text('Đang thực hiện').last);
      await tap(tester, find.text('Cập nhật'));
      expect(writes, 1);
      expect(
        find.text('Dữ liệu đã thay đổi. Vui lòng tải lại trước khi tiếp tục.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Đổi trạng thái'));
      await tap(tester, find.text('Đang bị chặn').last);
      await tap(tester, find.text('Cập nhật'));
      expect(find.text('Nhập lý do công việc bị chặn.'), findsOneWidget);
      expect(writes, 1);
      await tester.enterText(find.byType(TextFormField), 'Quá ngắn');
      await tap(tester, find.text('Cập nhật'));
      expect(
        find.text('Lý do bị chặn cần tối thiểu 15 ký tự.'),
        findsOneWidget,
      );
      expect(writes, 1);
      await tester.enterText(
        find.byType(TextFormField),
        'Chờ đầu vào từ nhóm thiết kế',
      );
      await tester.tap(find.text('Cập nhật'));
      await tester.pumpAndSettle();
      expect(writes, 2);
      expect(find.text('Đang cập nhật…'), findsOneWidget);
      final saving = find.widgetWithText(FilledButton, 'Đang cập nhật…');
      expect(tester.widget<FilledButton>(saving).onPressed, isNull);
      status = 'BLOCKED';
      token = 'version-3';
      pending.complete(json(taskFixture(status: status, token: token)));
      await tester.pumpAndSettle();
      expect(find.text('Đã cập nhật công việc.'), findsOneWidget);
      unavailable = true;
      await tap(tester, find.byTooltip('Làm mới công việc'));
      expect(
        find.text('Đang hiển thị dữ liệu từ lần tải thành công gần nhất.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(TaskDetailScreen),
          matching: find.text('Công việc thử nghiệm'),
        ),
        findsOneWidget,
      );
      unavailable = false;
      await tap(tester, find.text('Thử lại'));
      denied = true;
      await tester.scrollUntilVisible(
        find.byTooltip('Làm mới công việc'),
        -200,
        scrollable: find
            .descendant(
              of: find.byType(TaskDetailScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tap(tester, find.byTooltip('Làm mới công việc'));
      expect(
        find.descendant(
          of: find.byType(TaskDetailScreen),
          matching: find.text('Công việc thử nghiệm'),
        ),
        findsNothing,
      );
      expect(
        find.text('Tài khoản không được phép thực hiện thao tác này.'),
        findsOneWidget,
      );
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(TaskDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'project, milestones, meeting RSVP and long report feedback remain usable with large text',
    (tester) async {
      var rsvp = 'INVITED';
      var writes = 0;
      final auth = await startApp(tester, (request) async {
        final path = request.url.path;
        if (path == '/api/v1/projects/1') {
          return json({
            'id': 1,
            'teamId': 8,
            'code': 'SE28',
            'title': 'Đồ án kiểm thử',
            'status': 'ACTIVE',
            'description': 'Nội dung đồ án dài',
            'objectives': 'Mục tiêu',
            'problemStatement': 'Vấn đề',
            'expectedOutput': 'Kết quả',
          });
        }
        if (path == '/api/v1/teams/8') {
          return json({
            'id': 8,
            'code': 'SE28',
            'name': 'Nhóm SE28',
            'status': 'ACTIVE',
            'members': [
              {
                'userId': 17,
                'fullName': 'Sinh viên kiểm thử',
                'isLeader': true,
              },
            ],
          });
        }
        if (path == '/api/v1/milestones/project/1') {
          return json([
            {
              'id': 2,
              'projectId': 1,
              'title': 'Mốc khảo sát',
              'status': 'PLANNED',
              'dueDate': '2026-11-20',
              'sortOrder': 1,
            },
          ]);
        }
        if (path == '/api/v1/milestones/project/1/progress') {
          return json([
            {
              'milestoneId': 2,
              'progressPercentage': 50,
              'doneTasks': 1,
              'totalTasks': 2,
            },
          ]);
        }
        if (path == '/api/v1/projects/1/meetings') {
          return json(
            pageFixture([
              {
                'id': 3,
                'title': 'Họp tuần',
                'startAt': '2026-11-16T07:00:00Z',
                'status': 'SCHEDULED',
              },
            ]),
          );
        }
        if (path == '/api/v1/meetings/3') {
          return json({
            'id': 3,
            'projectId': 1,
            'title': 'Họp tuần',
            'status': 'SCHEDULED',
            'startAt': '2026-11-16T07:00:00Z',
            'participants': [],
            'feedbacks': [],
            'agenda': 'Trao đổi tiến độ',
          });
        }
        if (path == '/api/v1/meetings/3/collaboration') {
          return json({
            'myRsvp': {
              'userId': 17,
              'status': rsvp,
              'concurrencyToken': 'recipient-v1',
            },
            'concurrencyToken': 'meeting-v9',
          });
        }
        if (path == '/api/v1/meetings/3/rsvp') {
          writes++;
          expect(request.method, 'PUT');
          expect(jsonDecode(request.body), {
            'status': 'ACCEPTED',
            'concurrencyToken': 'recipient-v1',
          });
          rsvp = 'ACCEPTED';
          return json({'status': rsvp});
        }
        if (path == '/api/v1/projects/1/progress-reports') {
          return json(
            pageFixture([
              {
                'id': 4,
                'reportType': 'WEEKLY',
                'status': 'REVIEWED',
                'periodStart': '2026-11-09',
                'periodEnd': '2026-11-15',
                'submittedByName': 'Trưởng nhóm',
              },
            ]),
          );
        }
        if (path == '/api/v1/progress-reports/4') {
          return json({
            'id': 4,
            'reportType': 'WEEKLY',
            'status': 'REVIEWED',
            'periodStart': '2026-11-09',
            'periodEnd': '2026-11-15',
            'submittedByName': 'Trưởng nhóm',
            'summary': List.filled(
              20,
              'Báo cáo chi tiết về công việc của nhóm.',
            ).join('\n'),
            'feedbacks': [
              {
                'supervisorName': 'Giảng viên',
                'feedbackText': 'Cần bổ sung kết quả kiểm thử.',
                'createdAt': '2026-11-16T07:00:00Z',
              },
            ],
          });
        }
        return json({}, 404);
      });
      await tap(tester, find.text('Đồ án').last);
      expect(find.text('Mốc khảo sát'), findsOneWidget);
      await tap(tester, find.text('Lịch họp').first);
      final semantics = tester.ensureSemantics();
      final meetingLink = find.bySemanticsLabel(RegExp(r'^Họp tuần\n'));
      try {
        expect(
          tester
              .getSemantics(meetingLink)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
      await tap(tester, find.text('Họp tuần').first);
      await tap(tester, find.text('Phản hồi tham gia'));
      expect(writes, 0);
      await tap(tester, find.text('Tham gia'));
      expect(writes, 1);
      expect(find.text('Đã cập nhật phản hồi tham gia.'), findsOneWidget);
      expect(find.text('Đã chấp nhận'), findsOneWidget);
      await tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      await tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Báo cáo & phản hồi').first);
      await tap(tester, find.text('Báo cáo tuần · 09/11/2026'));
      await tester.binding.setSurfaceSize(const Size(320, 667));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cần bổ sung kết quả kiểm thử.'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportDetailScreen), findsOneWidget);
      final reading = tester.ensureSemantics();
      try {
        expect(
          find.bySemanticsLabel('Cần bổ sung kết quả kiểm thử.'),
          findsOneWidget,
        );
      } finally {
        reading.dispose();
      }
      expect(tester.takeException(), isNull);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(ReportDetailScreen), findsNothing);
    },
  );

  testWidgets(
    'inbox paginates, marks reads and accepts only the current recipients pending invite once',
    (tester) async {
      var reads = 0;
      var accepts = 0;
      var allReads = 0;
      var invitationStatus = 'PENDING';
      final accept = Completer<http.Response>();
      final pages = <String>[];
      await startApp(tester, (request) async {
        final path = request.url.path;
        if (path == '/api/v1/notifications') {
          final page = request.url.queryParameters['page'] ?? '1';
          pages.add(page);
          return json(
            pageFixture(
              [
                {
                  'id': int.parse(page),
                  'title': 'Thông báo $page',
                  'content': 'Nội dung thông báo',
                  'isRead': reads > 0,
                  'createdAt': '2026-11-16T07:00:00Z',
                },
              ],
              page: int.parse(page),
              pages: 2,
              total: 21,
            ),
          );
        }
        if (path == '/api/v1/notifications/2/read') {
          expect(request.method, 'PATCH');
          reads++;
          return http.Response('', 204);
        }
        if (path == '/api/v1/notifications/read-all') {
          expect(request.method, 'POST');
          allReads++;
          return http.Response('', 204);
        }
        if (path == '/api/v1/teams/invitations') {
          return json(
            pageFixture([
              {
                'id': 3,
                'teamId': 8,
                'teamName': 'Nhóm mới',
                'invitedUserId': 17,
                'status': invitationStatus,
                'invitedByName': 'Trưởng nhóm',
              },
              {
                'id': 4,
                'teamId': 9,
                'teamName': 'Lời mời người khác',
                'invitedUserId': 99,
                'status': 'PENDING',
              },
              {
                'id': 5,
                'teamId': 10,
                'teamName': 'Lời mời hết hạn',
                'invitedUserId': 17,
                'status': 'EXPIRED',
              },
            ]),
          );
        }
        if (path == '/api/v1/teams/invitations/3/accept') {
          accepts++;
          return accept.future;
        }
        return json({}, 404);
      });
      await tap(tester, find.text('Hộp thư').last);
      await tap(tester, find.byTooltip('Trang sau'));
      expect(pages, contains('2'));
      await tap(tester, find.text('Thông báo 2'));
      expect(reads, 1);
      expect(find.text('Nội dung thông báo'), findsOneWidget);
      await tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Đọc tất cả'));
      expect(allReads, 1);
      await tap(tester, find.text('Lời mời nhóm'));
      expect(find.text('Chấp nhận'), findsOneWidget);
      await tap(tester, find.text('Chấp nhận'));
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(accepts, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Chấp nhận'),
            )
            .onPressed,
        isNull,
      );
      invitationStatus = 'ACCEPTED';
      accept.complete(json({'id': 8}));
      await tester.pumpAndSettle();
      expect(find.text('Chấp nhận'), findsNothing);
      expect(find.text('Đã cập nhật hộp thư.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
