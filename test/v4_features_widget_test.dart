import 'dart:convert';

import 'package:ai_pms_mobile/app.dart';
import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/core/refresh_token_store.dart';
import 'package:ai_pms_mobile/features/ai/ai_screen.dart';
import 'package:ai_pms_mobile/features/auth/auth_controller.dart';
import 'package:ai_pms_mobile/features/workspace/project_quick_actions_screen.dart';
import 'package:ai_pms_mobile/features/workspace/report_editor_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'support/mobile_fixtures.dart';

Future<AuthController> _authed(
  MockClientHandler handler, {
  Map<String, Object?>? account,
}) async {
  final current = account ?? user;
  final api = ApiClient(
    origin: 'https://api.example.test',
    client: MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return json({...loginFixture(), 'user': current});
      }
      if (request.url.path == '/api/v1/auth/me') return json(current);
      if (request.url.path == '/api/v1/auth/logout') {
        return http.Response('', 204);
      }
      return handler(request);
    }),
  );
  final auth = AuthController(api: api, storage: MemoryRefreshTokenStore());
  await auth.signIn('user@example.test', 'secret');
  return auth;
}

void main() {
  testWidgets(
    'ReportEditorScreen prefills, creates draft and submits with concurrencyToken',
    (tester) async {
      var created = false;
      var submitted = false;
      String? submitToken;
      final auth = await _authed((request) async {
        if (request.url.path == '/api/v1/projects/1/progress-reports/prefill') {
          return json({
            'progressReportPeriodId': 9,
            'reportType': 'WEEKLY',
            'periodStart': '2026-11-16',
            'periodEnd': '2026-11-22',
            'suggested': {
              'summary': 'Hoàn tất API đồng bộ V4.',
              'completedWork': 'Xong module task.',
              'inProgressWork': 'Hoàn thiện báo cáo.',
              'blockers': '',
              'risks': '',
              'nextActions': 'Chuẩn bị demo.',
            },
            'evidence': [
              {'type': 'TASK', 'id': 12, 'title': 'Task API', 'status': 'DONE'},
            ],
            'insufficientData': false,
          });
        }
        if (request.url.path == '/api/v1/projects/1/progress-reports' &&
            request.method == 'POST') {
          created = true;
          return json({
            'id': 88,
            'projectId': 1,
            'status': 'DRAFT',
            'concurrencyToken': 'rpt-v1',
          }, 201);
        }
        if (request.url.path == '/api/v1/progress-reports/88/submit' &&
            request.method == 'POST') {
          submitted = true;
          submitToken = request.url.queryParameters['concurrencyToken'];
          return json({
            'id': 88,
            'projectId': 1,
            'status': 'SUBMITTED',
            'concurrencyToken': 'rpt-v2',
          });
        }
        return json({}, 404);
      });
      addTearDown(auth.dispose);

      await tester.pumpWidget(
        MaterialApp(home: ReportEditorScreen(auth: auth, projectId: 1)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hoàn tất API đồng bộ V4.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-submit-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Nộp báo cáo').last);
      await tester.pumpAndSettle();

      expect(created, isTrue);
      expect(submitted, isTrue);
      expect(submitToken, 'rpt-v1');
    },
  );

  testWidgets(
    'WorkingAgreementScreen renders sections and posts 1-tap acceptance',
    (tester) async {
      var accepted = false;
      final auth = await _authed((request) async {
        if (request.url.path == '/api/v1/projects/1/working-agreement' &&
            request.method == 'GET') {
          return json({
            'id': 5,
            'projectId': 1,
            'version': 2,
            'status': 'PUBLISHED',
            'contentJson': jsonEncode([
              {
                'title': 'Lịch họp cố định',
                'body': 'Họp thứ 4 hàng tuần lúc 20:00.',
              },
            ]),
            'concurrencyToken': 'wa-v2',
            'memberCount': 4,
            'acceptedByMe': accepted,
            'acceptances': accepted
                ? [
                    {'userId': 17, 'acceptedAt': '2026-11-24T06:00:00Z'},
                  ]
                : [],
          });
        }
        if (request.url.path ==
                '/api/v1/projects/1/working-agreement/acceptances' &&
            request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['agreementId'], 5);
          expect(body['concurrencyToken'], 'wa-v2');
          accepted = true;
          return json({'id': 5, 'acceptedByMe': true});
        }
        return json({}, 404);
      });
      addTearDown(auth.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkingAgreementScreen(
            auth: auth,
            projectId: 1,
            onChanged: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lịch họp cố định'), findsOneWidget);
      await tester.tap(find.byKey(const Key('accept-agreement-button')));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
      expect(find.text('Bạn đã xác nhận đồng thuận'), findsOneWidget);
    },
  );

  testWidgets(
    'PeerEvaluationScreen enforces >=30-char justification when score < 50%',
    (tester) async {
      var savedCount = 0;
      var submitted = false;
      final auth = await _authed((request) async {
        if (request.url.path == '/api/v1/projects/1/peer-evaluations/rounds') {
          return json(
            pageFixture([
              {
                'id': 3,
                'projectId': 1,
                'title': 'Vòng giữa kỳ',
                'status': 'OPEN',
                'opensAt': '2026-11-20T00:00:00Z',
                'closesAt': '2026-11-28T00:00:00Z',
                'concurrencyToken': 'pr-v1',
                'memberCount': 2,
                'canManage': false,
                'canSubmit': true,
                'reasons': [],
                'roster': [
                  {'userId': 22, 'majorId': 1, 'fullName': 'Nguyễn Văn B'},
                ],
              },
            ]),
          );
        }
        if (request.url.path == '/api/v1/projects/1/peer-evaluations/mine') {
          return json({
            'roundId': 3,
            'status': 'DRAFT',
            'submission': {
              'id': 11,
              'roundId': 3,
              'authorId': 17,
              'status': 'DRAFT',
              'concurrencyToken': 'pe-v1',
              'items': [
                {'targetUserId': 22, 'rating': 40, 'comment': ''},
              ],
            },
          });
        }
        if (request.url.path ==
                '/api/v1/projects/1/peer-evaluations/rounds/3/mine' &&
            request.method == 'PUT') {
          savedCount++;
          return json({
            'id': 11,
            'concurrencyToken': 'pe-v2',
            'status': 'DRAFT',
          });
        }
        if (request.url.path ==
                '/api/v1/projects/1/peer-evaluations/rounds/3/mine/submit' &&
            request.method == 'POST') {
          submitted = true;
          return json({'id': 11, 'status': 'SUBMITTED'});
        }
        return json({}, 404);
      });
      addTearDown(auth.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: PeerEvaluationScreen(
            auth: auth,
            projectId: 1,
            onChanged: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vòng giữa kỳ'));
      await tester.pumpAndSettle();

      // Score is 40% (< 50%) with empty comment -> blocked client-side before API call
      await tester.tap(find.byKey(const Key('peer-eval-submit-btn')));
      await tester.pumpAndSettle();
      expect(savedCount, 0);
      expect(find.textContaining('hiện có 0/30'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        'Thành viên bỏ lỡ hai buổi họp và chưa hoàn thành phần giao việc đúng hạn.',
      );
      await tester.tap(find.byKey(const Key('peer-eval-submit-btn')));
      await tester.pumpAndSettle();
      expect(savedCount, 1);
      expect(submitted, isTrue);
    },
  );

  testWidgets(
    'AssistantChatScreen streams NDJSON response and submits run feedback',
    (tester) async {
      int? sentRating;
      final auth = await _authed((request) async {
        if (request.url.path == '/api/v1/academic/assistant/conversations' &&
            request.method == 'POST') {
          return json({'id': 50, 'scope': 'ACADEMIC', 'revision': 1});
        }
        if (request.url.path == '/api/v1/academic/assistant/stream' &&
            request.method == 'POST') {
          final ndjson = [
            jsonEncode({'type': 'preview', 'text': 'Đang tổng hợp…'}),
            jsonEncode({
              'type': 'completed',
              'response': {
                'runId': 701,
                'answer': 'Sinh viên cần nộp báo cáo trước 23:59 Chủ nhật.',
                'answerType': 'GROUNDED',
                'citations': [],
                'projectEvidence': [],
                'followUpSuggestions': ['Xem mẫu báo cáo tuần'],
              },
            }),
          ].join('\n');
          return http.Response.bytes(
            utf8.encode(ndjson),
            200,
            headers: {'content-type': 'application/x-ndjson; charset=utf-8'},
          );
        }
        if (request.url.path == '/api/v1/academic/assistant/conversations/50') {
          return json({
            'conversation': {'id': 50, 'scope': 'ACADEMIC', 'revision': 2},
            'hasMore': false,
            'turns': [
              {
                'id': 1,
                'query': 'Hạn nộp báo cáo?',
                'sentAt': '2026-11-24T06:00:00Z',
                'response': {
                  'runId': 701,
                  'answer': 'Sinh viên cần nộp báo cáo trước 23:59 Chủ nhật.',
                  'answerType': 'GROUNDED',
                  'citations': [],
                  'projectEvidence': [],
                  'followUpSuggestions': ['Xem mẫu báo cáo tuần'],
                },
              },
            ],
          });
        }
        if (request.url.path ==
                '/api/v1/academic/assistant/runs/701/feedback' &&
            request.method == 'POST') {
          sentRating =
              (jsonDecode(request.body) as Map<String, dynamic>)['rating']
                  as int?;
          return json({'runId': 701, 'rating': sentRating});
        }
        return json({}, 404);
      });
      addTearDown(auth.dispose);

      await tester.pumpWidget(
        MaterialApp(home: AssistantChatScreen(auth: auth)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hạn nộp báo cáo?');
      await tester.tap(find.byTooltip('Gửi câu hỏi'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('23:59 Chủ nhật', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Xem mẫu báo cáo tuần'), findsOneWidget);

      await tester.tap(find.byTooltip('Hữu ích'));
      await tester.pumpAndSettle();
      expect(sentRating, 1);
    },
  );

  testWidgets(
    'Lecturer companion shell isolates from student mode, triages and posts report feedback at 320dp',
    (tester) async {
      tester.view
        ..physicalSize = const Size(320, 667)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var acceptedRequest = false;
      var feedbackPosted = false;
      final lecturer = {
        'id': 99,
        'email': 'gv@example.test',
        'fullName': 'TS. Nguyễn Văn Giảng',
        'roles': ['LECTURER'],
      };
      final auth = await _authed((request) async {
        if (request.url.path == '/api/v1/dashboards/supervisor') {
          return json({
            'asOfUtc': DateTime.now().toUtc().toIso8601String(),
            'workload': {
              'hasProfile': true,
              'isAvailable': true,
              'assignedProjects': 2,
              'profileMaxActiveProjects': 5,
            },
            'projectStates': [],
            'pendingProgressReviews': 1,
            'overdueTasks': 0,
            'projects': pageFixture([
              {
                'id': 1,
                'code': 'SE28',
                'title': 'Hệ thống AI-PMS',
                'status': 'ACTIVE',
                'teamId': 4,
                'semesterId': 1,
                'pendingProgressReviews': 1,
                'analysis': {
                  'riskLevel': 'LOW',
                  'progressSummary': {'progressPercentage': 75},
                },
                'majors': [
                  {'id': 1, 'code': 'SE', 'name': 'Software Engineering'},
                ],
              },
            ]),
          });
        }
        if (request.url.path == '/api/v1/supervisors/me/triage-queue') {
          return json({
            'asOfUtc': DateTime.now().toUtc().toIso8601String(),
            'totalCount': 1,
            'items': [
              {
                'kind': 'PROGRESS_REPORT_REVIEW',
                'id': 77,
                'projectId': 1,
                'title': 'Báo cáo tuần 6 nhóm SE28',
                'status': 'SUBMITTED',
                'severity': 'HIGH',
                'dueAt': '2026-11-25T10:00:00Z',
              },
            ],
          });
        }
        if (request.url.path == '/api/v1/supervisors/requests') {
          return json(
            pageFixture([
              {
                'id': 31,
                'projectId': 2,
                'projectTitle': 'Nhóm đăng ký mới',
                'status': acceptedRequest ? 'ACCEPTED' : 'PENDING',
                'requestedAt': '2026-11-23T08:00:00Z',
                'requestMessage': 'Kính nhờ thầy hướng dẫn nhóm em.',
              },
            ]),
          );
        }
        if (request.url.path == '/api/v1/supervisor-requests/31/accept') {
          acceptedRequest = true;
          return json({'id': 31, 'status': 'ACCEPTED'});
        }
        if (request.url.path == '/api/v1/progress-reports/77') {
          return json({
            'id': 77,
            'projectId': 1,
            'reportType': 'WEEKLY',
            'status': feedbackPosted ? 'REVIEWED' : 'SUBMITTED',
            'periodStart': '2026-11-16',
            'periodEnd': '2026-11-22',
            'submittedByName': 'Sinh viên A',
            'summary': 'Đã hoàn thành backend.',
            'concurrencyToken': 'r77-v1',
            'feedbacks': feedbackPosted
                ? [
                    {
                      'supervisorName': 'TS. Nguyễn Văn Giảng',
                      'feedbackText': 'Tiến độ tốt, chú ý test edge case.',
                      'createdAt': '2026-11-24T06:00:00Z',
                    },
                  ]
                : [],
          });
        }
        if (request.url.path == '/api/v1/progress-reports/77/feedback' &&
            request.method == 'POST') {
          feedbackPosted = true;
          return json({'id': 1}, 201);
        }
        return json({}, 404);
      }, account: lecturer);
      addTearDown(auth.dispose);

      await tester.pumpWidget(AiPmsApp(auth: auth));
      await tester.pumpAndSettle();

      expect(find.text('KHÔNG GIAN GIẢNG VIÊN'), findsOneWidget);
      expect(find.text('Công việc'), findsNothing);
      expect(find.text('Báo cáo tuần 6 nhóm SE28'), findsOneWidget);

      // Open Supervision Requests & Accept
      await tester.ensureVisible(find.text('Yêu cầu hướng dẫn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yêu cầu hướng dẫn'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Chấp nhận'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Chấp nhận').last);
      await tester.pumpAndSettle();
      expect(acceptedRequest, isTrue);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Open triage report item and post Lecturer feedback
      await tester.ensureVisible(find.text('Báo cáo tuần 6 nhóm SE28'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Báo cáo tuần 6 nhóm SE28'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('report-feedback-input')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('report-feedback-input')),
        'Tiến độ tốt, chú ý test edge case.',
      );
      await tester.ensureVisible(
        find.byKey(const Key('report-feedback-submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-feedback-submit')));
      await tester.pumpAndSettle();
      expect(feedbackPosted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
