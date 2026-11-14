import 'dart:convert';

import 'package:ai_pms_mobile/app.dart';
import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/core/refresh_token_store.dart';
import 'package:ai_pms_mobile/features/auth/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

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

void main() {
  testWidgets(
    'login validation sends no credentials and supports a small viewport',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 667));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var requests = 0;
      final api = ApiClient(
        origin: 'https://api.example.test',
        client: MockClient((_) async {
          requests++;
          return json({});
        }),
      );
      final auth = AuthController(api: api, storage: MemoryRefreshTokenStore());
      addTearDown(auth.dispose);
      addTearDown(api.close);
      await auth.restore();
      await tester.pumpWidget(AiPmsApp(auth: auth));
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('sign-in-button'));
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Nhập địa chỉ email hợp lệ.'), findsOneWidget);
      expect(requests, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'login, dashboard retry, profile, landscape and logout work together',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var dashboardCalls = 0;
      final api = ApiClient(
        origin: 'https://api.example.test',
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/api/v1/auth/login':
              return json({
                'accessToken': 'fixture-access',
                'tokenType': 'Bearer',
                'expiresAtUtc': DateTime.now()
                    .toUtc()
                    .add(const Duration(hours: 1))
                    .toIso8601String(),
                'refreshToken': 'fixture-refresh',
                'refreshTokenExpiresAtUtc': DateTime.now()
                    .toUtc()
                    .add(const Duration(days: 1))
                    .toIso8601String(),
                'user': user,
              });
            case '/api/v1/auth/me':
              return json(user);
            case '/api/v1/dashboards/student':
              dashboardCalls++;
              return dashboardCalls == 1 ? json({}, 503) : json(dashboard());
            case '/api/v1/auth/logout':
              return http.Response('', 204);
            default:
              return json({}, 404);
          }
        }),
      );
      final auth = AuthController(api: api, storage: MemoryRefreshTokenStore());
      addTearDown(auth.dispose);
      addTearDown(api.close);
      await auth.restore();
      await tester.pumpWidget(AiPmsApp(auth: auth));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('email-field')),
        'mobile-smoke@example.test',
      );
      await tester.enterText(
        find.byKey(const Key('password-field')),
        'fixture-password',
      );
      final login = find.byKey(const Key('sign-in-button'));
      await tester.ensureVisible(login);
      await tester.pumpAndSettle();
      await tester.tap(login);
      await tester.pumpAndSettle();
      expect(find.text('Chưa tải được tổng quan'), findsOneWidget);
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('Hệ thống quản lý tiến trình đồ án'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Tài khoản').last);
      await tester.pumpAndSettle();
      expect(find.text('mobile-smoke@example.test'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(812, 375));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final logout = find.byKey(const Key('sign-out-button'));
      await tester.scrollUntilVisible(logout, 200);
      await tester.pumpAndSettle();
      await tester.tap(logout);
      await tester.pumpAndSettle();
      expect(auth.status, SessionStatus.anonymous);
      await tester.scrollUntilVisible(
        find.byKey(const Key('email-field')),
        200,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('email-field')), findsOneWidget);
    },
  );
}
