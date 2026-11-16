import 'dart:async';

import 'package:ai_pms_mobile/app.dart';
import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/core/refresh_token_store.dart';
import 'package:ai_pms_mobile/features/auth/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'support/mobile_fixtures.dart';

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
      var dashboardForbidden = false;
      final refreshResponse = Completer<http.Response>();
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
              if (dashboardCalls == 4) return refreshResponse.future;
              if (dashboardCalls == 5 && dashboardForbidden) {
                return json({}, 403);
              }
              return dashboardCalls == 1 || dashboardCalls == 3
                  ? json({}, 503)
                  : json(dashboard());
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
      final refresh = find.byKey(const Key('refresh-dashboard-button'));
      expect(tester.getSize(refresh).shortestSide, greaterThanOrEqualTo(48));
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.text('Chưa cập nhật được dữ liệu'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
      expect(
        find.text('Bạn đang xem dữ liệu từ lần tải thành công gần nhất.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Thử lại'));
      await tester.pump();
      expect(dashboardCalls, 4);
      expect(tester.widget<IconButton>(refresh).onPressed, isNull);
      expect(find.text('62%'), findsOneWidget);
      refreshResponse.complete(json(dashboard()));
      await tester.pumpAndSettle();
      dashboardForbidden = true;
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(dashboardCalls, 5);
      expect(find.text('62%'), findsNothing);
      expect(
        find.text('Tài khoản không được phép thực hiện thao tác này.'),
        findsOneWidget,
      );
      expect(
        find.text('Bạn đang xem dữ liệu từ lần tải thành công gần nhất.'),
        findsNothing,
      );
      dashboardForbidden = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('62%'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(320, 667));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Hoàn thiện tài liệu thiết kế'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Tài khoản').last);
      await tester.pumpAndSettle();
      expect(find.text('mobile-smoke@example.test'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(812, 375));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final logout = find.byKey(const Key('sign-out-button'));
      await tester.scrollUntilVisible(
        logout,
        200,
        scrollable: find.byType(Scrollable).last,
      );
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
